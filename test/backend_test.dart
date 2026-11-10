import 'dart:convert';
import 'dart:io';

import 'package:admin_hub/backend/actions.dart';
import 'package:admin_hub/backend/backend.dart';
import 'package:admin_hub/backend/demo_backend.dart';
import 'package:admin_hub/backend/firebase_backend.dart';
import 'package:admin_hub/backend/local_store.dart';
import 'package:admin_hub/backend/models.dart';
import 'package:admin_hub/backend/service_account_backend.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('Firestore values round-trip, including lists', () {
    final t = DateTime.utc(2026, 1, 2, 3, 4, 5);
    final dec = decodeFields(encodeFields({'name': 'سارة', 'banned': true, 'points': 5, 'suspendedUntil': t, 'x': null, 'r': ['chat']}));
    expect(dec['name'], 'سارة');
    expect(dec['banned'], true);
    expect(dec['points'], 5);
    expect((dec['suspendedUntil'] as DateTime).toUtc(), t);
    expect(dec['x'], isNull);
    expect(dec['r'], ['chat']);
  });

  test('user status', () {
    final future = DateTime.now().add(const Duration(days: 1));
    expect(AppUser.fromMap('a', {'banned': true}).status, UserStatus.banned);
    expect(AppUser.fromMap('a', {'suspendedUntil': future}).status, UserStatus.suspended);
    expect(AppUser.fromMap('a', {'suspendedUntil': DateTime(2000)}).status, UserStatus.active);
    expect(AppUser.fromMap('a', {'restrictions': ['chat']}).status, UserStatus.restricted);
    expect(AppUser.fromMap('a', {'city': 'Riyadh', 'name': 'x'}).extra, {'city': 'Riyadh'});
  });

  test('content kinds and media', () {
    expect(contentKind('stories/s1').$1, 'قصة');
    expect(contentKind('users/u1/posts/p1').$1, 'منشور');
    expect(contentKind('moments/m1').$1, 'لحظة');
    const d = DataDoc('posts/p', {'caption': 'hi', 'imageUrl': 'https://x/y.jpg', 'likes': 4});
    expect(d.mainText, 'hi');
    expect(d.media, ['https://x/y.jpg']);
    expect(d.count(['likes']), 4);
  });

  test('demo: every action changes the user and is logged', () async {
    final b = DemoBackend();
    await b.connect();
    final a = UserActions(b);
    final apps = await b.listApps();
    expect(apps.any((x) => x.id == 'mind-ai'), isFalse);
    final app = apps.first.id;
    var u = (await b.listUsers(app)).firstWhere((u) => u.status == UserStatus.active);
    Future<AppUser> fresh() async => (await b.getUser(app, u.id))!;

    await a.ban(app, u, 'spam');
    expect((await fresh()).status, UserStatus.banned);
    await a.unban(app, await fresh());
    await a.suspend(app, await fresh(), DateTime.now().add(const Duration(hours: 1)), '');
    expect((await fresh()).status, UserStatus.suspended);
    await a.unsuspend(app, await fresh());
    expect((await fresh()).status, UserStatus.active);
    await a.warn(app, await fresh(), 'تنبيه');
    expect((await fresh()).warnings, 1);
    await a.setRestrictions(app, await fresh(), ['chat']);
    expect((await fresh()).status, UserStatus.restricted);
    await a.setRole(app, await fresh(), 'vip');
    await a.setPlan(app, await fresh(), 'max');
    await a.addPoints(app, await fresh(), 50);
    final f = await fresh();
    expect([f.role, f.plan], ['vip', 'max']);
    expect(f.points, u.points + 50);

    final info = await b.getInsights(app, f);
    expect(info.data, isNotEmpty);
    await b.deleteData(info.data.last.path);
    expect((await b.getInsights(app, f)).data.length, info.data.length - 1);

    final before = (await b.listUsers(app)).length;
    await a.delete(app, f);
    expect((await b.listUsers(app)).length, before - 1);
    expect((await b.listLogs()).length, greaterThanOrEqualTo(10));
  });

  group('service account backend', () {
    // A throwaway RSA key made at test time (no key is stored in the repo).
    late final String keyText = () {
      final dir = Directory.systemTemp.createTempSync('sa');
      final pem = '${dir.path}/k.pem';
      final r = Process.runSync('openssl', ['genpkey', '-algorithm', 'RSA', '-pkeyopt', 'rsa_keygen_bits:2048', '-out', pem]);
      if (r.exitCode != 0) throw StateError('openssl failed: ${r.stderr}');
      return jsonEncode({
        'type': 'service_account',
        'project_id': 'test-proj',
        'private_key_id': 'abc',
        'private_key': File(pem).readAsStringSync(),
        'client_email': 'hub@test-proj.iam.gserviceaccount.com',
      });
    }();
    late List<http.Request> calls;
    late Map<String, dynamic> account;

    ServiceAccountBackend make() {
      calls = [];
      account = {'localId': 'u1', 'email': 'a@b.c', 'displayName': 'Ali', 'createdAt': '1700000000000', 'providerUserInfo': [{'providerId': 'password'}]};
      final client = MockClient((req) async {
        calls.add(req);
        final url = req.url.toString();
        if (url.contains('oauth2.googleapis.com/token')) {
          return http.Response(jsonEncode({'access_token': 'tok', 'expires_in': 3600}), 200);
        }
        if (url.contains('accounts:batchGet')) return http.Response(jsonEncode({'users': [account]}), 200);
        if (url.contains('accounts:lookup')) return http.Response(jsonEncode({'users': [account]}), 200);
        if (url.contains('accounts:update')) {
          final b = jsonDecode(req.body) as Map<String, dynamic>;
          if (b.containsKey('disableUser')) account['disabled'] = b['disableUser'];
          if (b.containsKey('customAttributes')) account['customAttributes'] = b['customAttributes'];
          if (b.containsKey('displayName')) account['displayName'] = b['displayName'];
          return http.Response('{}', 200);
        }
        if (url.contains('accounts:delete')) return http.Response('{}', 200);
        if (url.endsWith('documents:listCollectionIds')) return http.Response(jsonEncode({'collectionIds': ['users']}), 200);
        if (url.endsWith('users/u1:listCollectionIds')) return http.Response('{}', 200);
        if (url.endsWith('documents/users/u1')) {
          return http.Response(jsonEncode({
            'name': 'projects/test-proj/databases/(default)/documents/users/u1',
            'fields': {'fcmToken': {'stringValue': 'T' * 150}, 'name': {'stringValue': 'Ali'}},
          }), 200);
        }
        if (url.contains(':runQuery')) return http.Response('[]', 200);
        if (url.contains('fcm.googleapis.com')) return http.Response('{"name":"m1"}', 200);
        return http.Response('{"error":{"message":"not found"}}', 404);
      });
      return ServiceAccountBackend(ServiceAccountBackend.parseKey(keyText), LocalStore('t'), client: client);
    }

    test('rejects a file that is not a key', () {
      expect(() => ServiceAccountBackend.parseKey('{"a":1}'), throwsA(isA<BackendError>()));
      expect(() => ServiceAccountBackend.parseKey('nope'), throwsA(isA<BackendError>()));
    });

    test('signs a JWT, lists users, bans, suspends and lifts', () async {
      final b = make();
      await b.connect();
      final jwt = Uri.splitQueryString(calls.first.body)['assertion']!;
      expect(jwt.split('.').length, 3);

      final a = UserActions(b);
      var u = (await b.listUsers('auth')).single;
      expect(u.displayName, 'Ali');
      expect(u.providers, ['password']);

      await a.ban('auth', u, 'spam');
      expect(account['disabled'], true);
      u = (await b.getUser('auth', 'u1'))!;
      expect(u.status, UserStatus.banned);
      expect(u.banReason, 'spam');
      expect(calls.where((c) => c.body.contains('validSince')), isNotEmpty);

      await a.unban('auth', u);
      expect(account['disabled'], false);
      await a.suspend('auth', (await b.getUser('auth', 'u1'))!, DateTime.now().add(const Duration(days: 1)), '');
      u = (await b.getUser('auth', 'u1'))!;
      expect(u.status, UserStatus.suspended);
      await a.unsuspend('auth', u);
      expect(account['disabled'], false);

      await a.setRestrictions('auth', (await b.getUser('auth', 'u1'))!, ['chat']);
      await a.setPlan('auth', (await b.getUser('auth', 'u1'))!, 'pro');
      await a.editProfile('auth', (await b.getUser('auth', 'u1'))!, name: 'Ali 2', email: 'a@b.c', phone: '');
      u = (await b.getUser('auth', 'u1'))!;
      expect(u.restrictions, ['chat']);
      expect(u.plan, 'pro');
      expect(u.name, 'Ali 2');

      await a.delete('auth', u);
      expect(calls.last.url.toString(), contains('accounts:delete'));
      expect((await b.listLogs()).first.action, 'حذف الحساب');
    });

    test('message goes out as a push to the saved FCM token', () async {
      final b = make();
      final u = (await b.listUsers('auth')).single;
      final result = await UserActions(b).message('auth', u, 'مرحبا');
      expect(result, contains('✓'));
      final push = calls.firstWhere((c) => c.url.host == 'fcm.googleapis.com');
      final msg = (jsonDecode(push.body) as Map)['message'] as Map;
      expect(msg['token'], 'T' * 150);
      expect((msg['notification'] as Map)['body'], 'مرحبا');
    });

    test('an account disabled in the console shows as banned', () async {
      final b = make();
      account['disabled'] = true;
      expect((await b.listUsers('auth')).single.status, UserStatus.banned);
    });
  });
}
