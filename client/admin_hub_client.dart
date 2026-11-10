// Copy this file into any of your Flutter apps (needs `http` and
// `shared_preferences`). It registers the user in the hub and tells you if
// the admin banned, suspended or deleted them.
//
//   final hub = AdminHubClient(apiKey: 'AIza…', projectId: 'my-apps-12345', appId: 'my-app');
//   final s = await hub.check(name: name, email: email);
//   if (s.mustSignOut) { /* sign the user out */ }
//   if (!s.allowed) { /* show s.message and block the app */ }
//   if (s.adminMessage.isNotEmpty) { /* show it once */ }
//   if (s.isRestricted('chat')) { /* hide the chat feature */ }
//   hub.logEvent('نشر منشوراً', detail: caption, icon: '📝');   // shows in the hub's activity tab
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

enum HubState { active, suspended, banned, deleted, offline }

class HubStatus {
  final HubState state;
  final DateTime? until;
  final String reason;
  final String role, plan, adminMessage;
  final int points, warnings;
  final bool verified, mustSignOut;
  final List<String> restrictions;
  const HubStatus(this.state,
      {this.until,
      this.reason = '',
      this.role = 'user',
      this.plan = 'free',
      this.adminMessage = '',
      this.points = 0,
      this.warnings = 0,
      this.verified = false,
      this.mustSignOut = false,
      this.restrictions = const []});

  bool isRestricted(String feature) => restrictions.contains(feature);

  /// Offline counts as allowed so a bad connection never locks people out.
  bool get allowed => state == HubState.active || state == HubState.offline;

  String get message => switch (state) {
        HubState.banned => 'تم حظر حسابك${reason.isEmpty ? '' : ': $reason'}',
        HubState.suspended => 'حسابك محجوب مؤقتاً حتى ${until?.toLocal()}${reason.isEmpty ? '' : '\n$reason'}',
        HubState.deleted => 'تم حذف حسابك',
        _ => '',
      };
}

class AdminHubClient {
  final String apiKey, projectId, appId;
  AdminHubClient({required this.apiKey, required this.projectId, required this.appId});

  String get _doc => 'https://firestore.googleapis.com/v1/projects/$projectId/databases/(default)/documents/apps/$appId/users';

  /// Call on app start (and after sign-in). Safe to call often.
  Future<HubStatus> check({required String name, required String email}) async {
    try {
      final p = await SharedPreferences.getInstance();
      final auth = await _auth(p);
      if (auth == null) return const HubStatus(HubState.offline);
      final (token, uid) = auth;
      final h = {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'};
      final url = '$_doc/$uid';
      final registered = p.getBool('hub_registered_$appId') ?? false;

      final got = await http.get(Uri.parse(url), headers: h);
      if (got.statusCode == 404) {
        if (registered) return const HubStatus(HubState.deleted);
        final now = DateTime.now().toUtc().toIso8601String();
        final res = await http.patch(
          Uri.parse('$url?currentDocument.exists=false'),
          headers: h,
          body: jsonEncode({'fields': {
            'name': {'stringValue': name},
            'email': {'stringValue': email},
            'createdAt': {'timestampValue': now},
            'lastSeen': {'timestampValue': now},
          }}),
        );
        if (res.statusCode < 300) await p.setBool('hub_registered_$appId', true);
        return const HubStatus(HubState.active);
      }
      if (got.statusCode >= 300) return const HubStatus(HubState.offline);
      await p.setBool('hub_registered_$appId', true);

      final f = (jsonDecode(got.body)['fields'] as Map?) ?? {};
      // Keep the hub's copy of name/email/last seen fresh.
      await http.patch(
        Uri.parse('$url?updateMask.fieldPaths=name&updateMask.fieldPaths=email&updateMask.fieldPaths=lastSeen'),
        headers: h,
        body: jsonEncode({'fields': {
          'name': {'stringValue': name},
          'email': {'stringValue': email},
          'lastSeen': {'timestampValue': DateTime.now().toUtc().toIso8601String()},
        }}),
      );
      String str(String k) => '${(f[k] as Map?)?['stringValue'] ?? ''}';
      int num(String k) => int.tryParse('${(f[k] as Map?)?['integerValue'] ?? 0}') ?? 0;
      DateTime? time(String k) => DateTime.tryParse('${(f[k] as Map?)?['timestampValue'] ?? ''}');
      final reason = str('banReason');
      final logoutAt = time('forceLogoutAt');
      final seenLogout = DateTime.tryParse(p.getString('hub_logout_$appId') ?? '');
      final mustSignOut = logoutAt != null && (seenLogout == null || logoutAt.isAfter(seenLogout));
      if (mustSignOut) await p.setString('hub_logout_$appId', logoutAt.toIso8601String());
      final msgAt = time('adminMessageAt');
      final seenMsg = DateTime.tryParse(p.getString('hub_msg_$appId') ?? '');
      final newMsg = msgAt != null && (seenMsg == null || msgAt.isAfter(seenMsg));
      if (newMsg) await p.setString('hub_msg_$appId', msgAt.toIso8601String());
      final until = time('suspendedUntil');
      final banned = (f['banned'] as Map?)?['booleanValue'] == true;
      return HubStatus(
        banned
            ? HubState.banned
            : (until != null && until.isAfter(DateTime.now()) ? HubState.suspended : HubState.active),
        until: until,
        reason: reason,
        role: str('role').isEmpty ? 'user' : str('role'),
        plan: str('plan').isEmpty ? 'free' : str('plan'),
        adminMessage: newMsg ? str('adminMessage') : '',
        points: num('points'),
        warnings: num('warnings'),
        verified: (f['verified'] as Map?)?['booleanValue'] == true,
        mustSignOut: mustSignOut,
        restrictions: [
          for (final v in (((f['restrictions'] as Map?)?['arrayValue'] as Map?)?['values'] as List?) ?? const [])
            '${(v as Map)['stringValue']}',
        ],
      );
    } catch (_) {
      return const HubStatus(HubState.offline);
    }
  }

  /// Records something the user did; it shows on their activity timeline
  /// in the hub. Fire and forget.
  Future<void> logEvent(String type, {String detail = '', String icon = '•'}) async {
    try {
      final p = await SharedPreferences.getInstance();
      final auth = await _auth(p);
      if (auth == null) return;
      final (token, uid) = auth;
      await http.post(
        Uri.parse('$_doc/$uid/events'),
        headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'},
        body: jsonEncode({'fields': {
          'type': {'stringValue': type},
          'detail': {'stringValue': detail},
          'icon': {'stringValue': icon},
          'at': {'timestampValue': DateTime.now().toUtc().toIso8601String()},
        }}),
      );
    } catch (_) {}
  }

  /// Anonymous Firebase account per install, kept in SharedPreferences.
  Future<(String, String)?> _auth(SharedPreferences p) async {
    final refresh = p.getString('hub_refresh');
    final http.Response res;
    if (refresh == null) {
      res = await http.post(
        Uri.parse('https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=$apiKey'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'returnSecureToken': true}),
      );
      if (res.statusCode != 200) return null;
      final b = jsonDecode(res.body);
      await p.setString('hub_refresh', b['refreshToken']);
      return (b['idToken'] as String, b['localId'] as String);
    }
    res = await http.post(
      Uri.parse('https://securetoken.googleapis.com/v1/token?key=$apiKey'),
      body: {'grant_type': 'refresh_token', 'refresh_token': refresh},
    );
    if (res.statusCode != 200) return null;
    final b = jsonDecode(res.body);
    await p.setString('hub_refresh', b['refresh_token']);
    return (b['id_token'] as String, b['user_id'] as String);
  }
}
