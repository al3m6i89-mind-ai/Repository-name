import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

/// Admin logs and notes kept on this device, for connections that have no
/// shared database of their own.
class LocalStore {
  final String scope;
  LocalStore(this.scope);

  Future<SharedPreferences?> _p() async {
    try {
      return await SharedPreferences.getInstance();
    } catch (_) {
      return null;
    }
  }

  Future<String> getNote(String key) async => (await _p())?.getString('note/$scope/$key') ?? '';

  Future<void> setNote(String key, String text) async => (await _p())?.setString('note/$scope/$key', text);

  Future<void> addLog(LogEntry e) async {
    final p = await _p();
    if (p == null) return;
    final list = p.getStringList('logs/$scope') ?? [];
    list.insert(
      0,
      jsonEncode({
        'appId': e.appId,
        'userId': e.userId,
        'userName': e.userName,
        'action': e.action,
        'detail': e.detail,
        'by': e.by,
        'at': e.at.toIso8601String(),
      }),
    );
    await p.setStringList('logs/$scope', list.take(500).toList());
  }

  Future<List<LogEntry>> listLogs({int limit = 200}) async {
    final p = await _p();
    final out = <LogEntry>[];
    for (final s in (p?.getStringList('logs/$scope') ?? const <String>[]).take(limit)) {
      try {
        final m = jsonDecode(s) as Map<String, dynamic>;
        out.add(LogEntry(
          appId: m['appId'] ?? '',
          userId: m['userId'] ?? '',
          userName: m['userName'] ?? '',
          action: m['action'] ?? '',
          detail: m['detail'] ?? '',
          by: m['by'] ?? '',
          at: DateTime.tryParse(m['at'] ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0),
        ));
      } catch (_) {}
    }
    return out;
  }

  Future<void> clear() async {
    final p = await _p();
    if (p == null) return;
    for (final k in p.getKeys().where((k) => k.startsWith('note/$scope/') || k == 'logs/$scope').toList()) {
      await p.remove(k);
    }
  }
}
