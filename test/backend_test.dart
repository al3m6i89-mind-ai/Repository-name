import 'package:admin_hub/backend/backend.dart';
import 'package:admin_hub/backend/demo_backend.dart';
import 'package:admin_hub/backend/firebase_backend.dart';
import 'package:admin_hub/backend/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Firestore values round-trip', () {
    final t = DateTime.utc(2026, 1, 2, 3, 4, 5);
    final enc = encodeFields({'name': 'سارة', 'banned': true, 'points': 5, 'suspendedUntil': t, 'x': null});
    final dec = decodeFields(enc);
    expect(dec['name'], 'سارة');
    expect(dec['banned'], true);
    expect(dec['points'], 5);
    expect((dec['suspendedUntil'] as DateTime).toUtc(), t);
    expect(dec['x'], isNull);
  });

  test('user status from fields', () {
    final future = DateTime.now().add(const Duration(days: 1));
    expect(userFromFields('a', {'banned': true}).status, UserStatus.banned);
    expect(userFromFields('a', {'suspendedUntil': future}).status, UserStatus.suspended);
    expect(userFromFields('a', {'suspendedUntil': DateTime(2000)}).status, UserStatus.active);
    expect(userFromFields('a', {'plan': 'Pro', 'name': 'x'}).extra, {'plan': 'Pro'});
  });

  test('demo backend: sign in, ban, suspend, delete', () async {
    final b = DemoBackend();
    expect(() => b.signIn('x@y.com', 'bad'), throwsA(isA<BackendError>()));
    await b.signIn(DemoBackend.demoEmail, DemoBackend.demoPassword);
    final apps = await b.listApps();
    expect(apps.any((a) => a.id == 'mind-ai'), isFalse);
    await b.saveApp(const AppInfo(id: 'new-app', name: 'جديد'));
    expect((await b.listApps()).any((a) => a.id == 'new-app'), isTrue);

    final app = apps.first.id;
    var u = (await b.listUsers(app)).firstWhere((u) => u.status == UserStatus.active);
    await b.setBanned(app, u.id, true, reason: 'r');
    expect((await b.listUsers(app)).firstWhere((x) => x.id == u.id).status, UserStatus.banned);
    await b.setBanned(app, u.id, false);
    await b.setSuspendedUntil(app, u.id, DateTime.now().add(const Duration(hours: 1)));
    expect((await b.listUsers(app)).firstWhere((x) => x.id == u.id).status, UserStatus.suspended);
    await b.setSuspendedUntil(app, u.id, null);
    expect((await b.listUsers(app)).firstWhere((x) => x.id == u.id).status, UserStatus.active);
    final before = (await b.listUsers(app)).length;
    await b.deleteUser(app, u.id);
    expect((await b.listUsers(app)).length, before - 1);
  });
}
