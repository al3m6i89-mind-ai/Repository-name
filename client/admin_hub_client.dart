// Copy this file into any of your Flutter apps (needs `http` and
// `shared_preferences`). It registers the user in the hub and tells you if
// the admin banned, suspended or deleted them.
//
//   final hub = AdminHubClient(apiKey: 'AIza…', projectId: 'my-apps-12345', appId: 'my-app');
//   final s = await hub.check(name: name, email: email);
//   if (!s.allowed) { /* show s.message and block the app */ }
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

enum HubState { active, suspended, banned, deleted, offline }

class HubStatus {
  final HubState state;
  final DateTime? until;
  final String reason;
  const HubStatus(this.state, {this.until, this.reason = ''});

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
      final reason = '${(f['banReason'] as Map?)?['stringValue'] ?? ''}';
      if ((f['banned'] as Map?)?['booleanValue'] == true) return HubStatus(HubState.banned, reason: reason);
      final until = DateTime.tryParse('${(f['suspendedUntil'] as Map?)?['timestampValue'] ?? ''}');
      if (until != null && until.isAfter(DateTime.now())) return HubStatus(HubState.suspended, until: until, reason: reason);
      return const HubStatus(HubState.active);
    } catch (_) {
      return const HubStatus(HubState.offline);
    }
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
