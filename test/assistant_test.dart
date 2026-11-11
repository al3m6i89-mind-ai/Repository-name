import 'package:admin_hub/assistant/assistant.dart';
import 'package:admin_hub/backend/models.dart';
import 'package:admin_hub/backend/session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late HubSession s;
  late Assistant a;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    s = HubSession();
    await s.load();
    await s.add(Connection(id: 'demo', type: ConnectionType.demo, label: 'تجريبي', icon: '🧪'));
    a = Assistant(s);
  });

  int total() => s.apps.fold(0, (n, d) => n + d.users.length);

  test('normalises Arabic', () {
    expect(Assistant.norm('أحمد إبراهيم؟'), 'احمد ابراهيم');
    expect(Assistant.norm('مدة ٣ أيام'), 'مده 3 ايام');
  });

  test('counts', () {
    expect(a.answer('كم مستخدم عندي؟').text, contains('${total()}'));
    final banned = s.apps.expand((d) => d.users).where((u) => u.status == UserStatus.banned).length;
    expect(a.answer('كم واحد محظور').text, contains('$banned'));
    final shop = s.apps.firstWhere((d) => d.app.id == 'shop');
    expect(a.answer('كم مستخدم في متجري').text, contains('${shop.users.length}'));
  });

  test('summary, lists and search', () {
    expect(a.answer('ملخص اليوم').text, contains('المستخدمين: ${total()}'));
    expect(a.answer('مين المحظورين؟').users, isNotEmpty);
    final r = a.answer('ابحث عن شهد');
    expect(r.users.single.$2.name, 'شهد العتيبي');
    expect(a.answer('شهد العتيبي').users.single.$2.name, 'شهد العتيبي');
  });

  test('commands ask first, then run', () async {
    final r = a.answer('احجب شهد ٣ أيام');
    expect(r.action, isNotNull);
    expect(r.action!.label, contains('3 يوم'));
    expect(await r.action!.run(), contains('✓'));
    final u = s.apps.expand((d) => d.users).firstWhere((u) => u.name == 'شهد العتيبي');
    expect(u.status, UserStatus.suspended);

    final m = a.answer('ارسل لشهد: أهلاً بك');
    expect(m.action!.label, contains('أهلاً بك'));

    expect(a.answer('احظر').text, contains('مين'));
    expect(a.answer('احظر زززز').text, contains('ما لقيت'));
  });
}
