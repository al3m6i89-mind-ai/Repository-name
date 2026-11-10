import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'backend.dart';
import 'demo_backend.dart';
import 'firebase_backend.dart';
import 'local_store.dart';
import 'models.dart';
import 'service_account_backend.dart';

enum ConnectionType { demo, serviceAccount, hub }

/// One connected account: a Firebase project (or the demo).
class Connection {
  final String id;
  final ConnectionType type;
  String label;
  String icon;
  final Map<String, String> data;

  Connection({required this.id, required this.type, required this.label, this.icon = '🔥', Map<String, String>? data})
      : data = data ?? {};

  String get projectId => data['projectId'] ?? '';

  String get typeLabel => switch (type) {
        ConnectionType.demo => 'تجريبي',
        ConnectionType.serviceAccount => 'حساب خدمة · تحكم كامل',
        ConnectionType.hub => 'إيميل وكلمة مرور',
      };

  Map<String, Object?> toJson() => {'id': id, 'type': type.name, 'label': label, 'icon': icon, 'data': data};

  static Connection fromJson(Map<String, dynamic> j) => Connection(
        id: j['id'],
        type: ConnectionType.values.byName(j['type']),
        label: j['label'] ?? '',
        icon: j['icon'] ?? '🔥',
        data: (j['data'] as Map? ?? {}).map((k, v) => MapEntry('$k', '$v')),
      );
}

/// State of a connection after trying to reach it.
class Linked {
  final Connection connection;
  final AdminBackend backend;
  String? error;
  Linked(this.connection, this.backend, {this.error});
  bool get ok => error == null;
}

/// All connected accounts. Screens read apps and users through this.
class HubSession extends ChangeNotifier {
  final List<Linked> linked = [];
  String lockHash = '';
  bool loaded = false;

  static AdminBackend createBackend(Connection c, {String? password}) => switch (c.type) {
        ConnectionType.demo => DemoBackend(),
        ConnectionType.serviceAccount =>
          ServiceAccountBackend(ServiceAccountBackend.parseKey(c.data['serviceAccount'] ?? ''), LocalStore(c.id)),
        ConnectionType.hub => FirebaseBackend(
            apiKey: c.data['apiKey'] ?? '',
            projectId: c.data['projectId'] ?? '',
            email: c.data['email'],
            password: password,
            refreshToken: c.data['refreshToken'],
          ),
      };

  Future<void> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      lockHash = p.getString('lockHash') ?? '';
      final list = (jsonDecode(p.getString('connections') ?? '[]') as List).cast<Map<String, dynamic>>();
      for (final j in list) {
        try {
          final c = Connection.fromJson(j);
          linked.add(Linked(c, createBackend(c)));
        } catch (_) {}
      }
    } catch (_) {}
    loaded = true;
    await Future.wait(linked.map(_reach));
    notifyListeners();
  }

  Future<void> _reach(Linked l) async {
    try {
      await l.backend.connect();
      l.error = null;
    } catch (e) {
      l.error = '$e';
    }
  }

  Future<void> retry(Linked l) async {
    await _reach(l);
    notifyListeners();
  }

  Future<void> save() async {
    try {
      final p = await SharedPreferences.getInstance();
      for (final l in linked) {
        l.connection.data.addAll(l.backend.sessionData);
      }
      await p.setString('connections', jsonEncode([for (final l in linked) l.connection.toJson()]));
      await p.setString('lockHash', lockHash);
    } catch (_) {}
  }

  /// Connects first; only a working account is added. Throws [BackendError].
  Future<void> add(Connection c, {String? password}) async {
    final b = createBackend(c, password: password);
    await b.connect();
    c.data.remove('password');
    linked.removeWhere((l) => l.connection.id == c.id);
    linked.add(Linked(c, b));
    await save();
    notifyListeners();
  }

  Future<void> remove(Linked l) async {
    linked.remove(l);
    await LocalStore(l.connection.id).clear();
    await save();
    notifyListeners();
  }

  Future<void> rename(Linked l, String label, String icon) async {
    l.connection
      ..label = label
      ..icon = icon;
    await save();
    notifyListeners();
  }

  Linked? byId(String id) {
    for (final l in linked) {
      if (l.connection.id == id) return l;
    }
    return null;
  }

  AdminBackend backendOf(AppInfo app) => byId(app.connectionId)!.backend;

  /// Apps from every reachable account.
  Future<List<AppInfo>> allApps() async {
    final out = <AppInfo>[];
    for (final l in linked.where((l) => l.ok)) {
      try {
        final apps = await l.backend.listApps();
        for (final a in apps) {
          // A whole-project connection shows under the name you gave it.
          final named = l.connection.type == ConnectionType.serviceAccount
              ? AppInfo(id: a.id, name: l.connection.label, icon: l.connection.icon, description: a.description)
              : a;
          out.add(named.withConnection(l.connection.id));
        }
      } catch (e) {
        l.error = '$e';
      }
    }
    return out;
  }

  Future<List<(AppInfo, LogEntry)>> allLogs({int limit = 300}) async {
    final apps = {for (final a in await allApps()) a.key: a};
    final out = <(AppInfo, LogEntry)>[];
    for (final l in linked.where((l) => l.ok)) {
      try {
        for (final e in await l.backend.listLogs(limit: limit)) {
          final app = apps['${l.connection.id}/${e.appId}'] ??
              AppInfo(id: e.appId, name: e.appId, connectionId: l.connection.id);
          out.add((app, e));
        }
      } catch (_) {}
    }
    out.sort((a, b) => b.$2.at.compareTo(a.$2.at));
    return out.take(limit).toList();
  }

  // Optional lock on the hub itself.

  static String hash(String s) => sha256.convert(utf8.encode('admin-hub-lock:$s')).toString();

  bool checkLock(String s) => lockHash.isEmpty || hash(s) == lockHash;

  Future<void> setLock(String password) async {
    lockHash = password.isEmpty ? '' : hash(password);
    await save();
    notifyListeners();
  }
}
