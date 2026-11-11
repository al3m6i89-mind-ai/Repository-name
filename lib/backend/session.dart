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
  bool connecting;
  Linked(this.connection, this.backend, {this.error, this.connecting = false});
  bool get ok => error == null;
  bool get ready => ok && !connecting;
}

/// One app with its users, as last fetched (also kept on the device so the
/// hub opens instantly with the previous numbers).
class AppData {
  final AppInfo app;
  List<AppUser> users;
  String? error;
  DateTime? updated;
  AppData(this.app, this.users, {this.error, this.updated});
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
    await _restoreCache();
    loaded = true;
    notifyListeners();
    // Connect and refresh in the background; screens show the cached data
    // meanwhile.
    _startup = _connectAll().then((_) => refreshAll());
  }

  Future<void>? _startup;

  /// Completes when the first background refresh after launch is done.
  Future<void> get ready => _startup ?? Future.value();

  Future<void> _connectAll() async {
    for (final l in linked) {
      l.connecting = true;
    }
    await Future.wait(linked.map(_reach));
  }

  Future<void> _reach(Linked l) async {
    l.connecting = true;
    try {
      await l.backend.connect();
      l.error = null;
    } catch (e) {
      l.error = '$e';
    }
    l.connecting = false;
  }

  Future<void> retry(Linked l) async {
    await _reach(l);
    notifyListeners();
    await refreshAll();
  }

  // Data ------------------------------------------------------------------------

  final Map<String, AppData> data = {};
  bool refreshing = false;
  DateTime? lastRefresh;
  Future<void>? _refreshing;

  /// Apps of connected accounts, in account order.
  List<AppData> get apps => [
        for (final l in linked)
          for (final d in data.values)
            if (d.app.connectionId == l.connection.id) d,
      ];

  AppData? dataOf(AppInfo app) => data[app.key];

  /// Fetches apps and users of every account at the same time.
  Future<void> refreshAll() {
    return _refreshing ??= () async {
      refreshing = true;
      notifyListeners();
      try {
        await Future.wait([for (final l in linked.where((l) => l.ready)) _refreshAccount(l)]);
        lastRefresh = DateTime.now();
        _saveCache();
      } finally {
        refreshing = false;
        _refreshing = null;
        notifyListeners();
      }
    }();
  }

  Future<void> _refreshAccount(Linked l) async {
    List<AppInfo> apps;
    try {
      apps = [for (final a in await l.backend.listApps()) _named(l, a)];
    } catch (e) {
      l.error = '$e';
      return;
    }
    data.removeWhere((k, d) => d.app.connectionId == l.connection.id && !apps.any((a) => a.key == k));
    await Future.wait(apps.map((a) async {
      final d = data[a.key] ?? AppData(a, []);
      try {
        d.users = await l.backend.listUsers(a.id);
        d.error = null;
        d.updated = DateTime.now();
      } catch (e) {
        d.error = '$e';
      }
      data[a.key] = AppData(a, d.users, error: d.error, updated: d.updated);
    }));
  }

  Future<void> refreshApp(AppInfo app) async {
    final l = byId(app.connectionId);
    if (l == null) return;
    final d = data[app.key] ?? AppData(app, []);
    try {
      d.users = await l.backend.listUsers(app.id);
      d.error = null;
      d.updated = DateTime.now();
    } catch (e) {
      d.error = '$e';
    }
    data[app.key] = d;
    notifyListeners();
    _saveCache();
  }

  /// Puts a changed user into the cache right away.
  void putUser(AppInfo app, AppUser u) {
    final d = data[app.key];
    if (d == null) return;
    final i = d.users.indexWhere((x) => x.id == u.id);
    i >= 0 ? d.users[i] = u : d.users.add(u);
    notifyListeners();
    _saveCache();
  }

  void dropUser(AppInfo app, String userId) {
    data[app.key]?.users.removeWhere((u) => u.id == userId);
    notifyListeners();
    _saveCache();
  }

  AppInfo _named(Linked l, AppInfo a) {
    final named = l.connection.type == ConnectionType.serviceAccount
        ? AppInfo(id: a.id, name: l.connection.label, icon: l.connection.icon, description: a.description)
        : a;
    return named.withConnection(l.connection.id);
  }

  static Object? _enc(Object? v) => v is DateTime ? {r'$t': v.toIso8601String()} : v;
  static Object? _dec(Object? v) => v is Map && v.containsKey(r'$t') ? DateTime.tryParse('${v[r'$t']}') : v;

  Future<void> _saveCache() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(
        'cache_v1',
        jsonEncode([
          for (final d in data.values)
            {
              'app': {'id': d.app.id, 'name': d.app.name, 'icon': d.app.icon, 'description': d.app.description, 'c': d.app.connectionId},
              'updated': d.updated?.toIso8601String(),
              'users': [
                for (final u in d.users) {'id': u.id, 'f': u.toMap().map((k, v) => MapEntry(k, _enc(v)))},
              ],
            },
        ]),
      );
    } catch (_) {}
  }

  Future<void> _restoreCache() async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString('cache_v1');
      if (raw == null) return;
      for (final j in (jsonDecode(raw) as List).cast<Map<String, dynamic>>()) {
        final a = j['app'] as Map<String, dynamic>;
        if (byId('${a['c']}') == null) continue;
        final app = AppInfo(id: a['id'], name: a['name'], icon: a['icon'] ?? '📱', description: a['description'] ?? '', connectionId: a['c']);
        data[app.key] = AppData(
          app,
          [
            for (final u in (j['users'] as List).cast<Map<String, dynamic>>())
              AppUser.fromMap(u['id'], (u['f'] as Map<String, dynamic>).map((k, v) => MapEntry(k, _dec(v)))),
          ],
          updated: DateTime.tryParse('${j['updated']}'),
        );
      }
    } catch (_) {}
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
    await refreshAll();
  }

  Future<void> remove(Linked l) async {
    linked.remove(l);
    data.removeWhere((_, d) => d.app.connectionId == l.connection.id);
    _saveCache();
    await LocalStore(l.connection.id).clear();
    await save();
    notifyListeners();
  }

  Future<void> rename(Linked l, String label, String icon) async {
    l.connection
      ..label = label
      ..icon = icon;
    await save();
    for (final d in data.values.where((d) => d.app.connectionId == l.connection.id).toList()) {
      data[d.app.key] = AppData(_named(l, d.app), d.users, error: d.error, updated: d.updated);
    }
    notifyListeners();
  }

  Linked? byId(String id) {
    for (final l in linked) {
      if (l.connection.id == id) return l;
    }
    return null;
  }

  AdminBackend backendOf(AppInfo app) => byId(app.connectionId)!.backend;

  /// Apps from every reachable account (fetched if not loaded yet).
  Future<List<AppInfo>> allApps() async {
    if (data.isEmpty) await refreshAll();
    return [for (final d in apps) d.app];
  }

  Future<List<(AppInfo, LogEntry)>> allLogs({int limit = 300}) async {
    final apps = {for (final a in await allApps()) a.key: a};
    final out = <(AppInfo, LogEntry)>[];
    await Future.wait(linked.where((l) => l.ready).map((l) async {
      try {
        for (final e in await l.backend.listLogs(limit: limit)) {
          final app = apps['${l.connection.id}/${e.appId}'] ??
              AppInfo(id: e.appId, name: e.appId, connectionId: l.connection.id);
          out.add((app, e));
        }
      } catch (_) {}
    }));
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
