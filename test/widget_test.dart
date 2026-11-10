import 'package:admin_hub/backend/session.dart';
import 'package:admin_hub/main.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('demo: welcome → dashboard → app → user → control', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.6;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(AdminHubApp(session: HubSession(), theme: ThemeController()));
    await tester.pumpAndSettle();
    expect(find.text('ربط حساب Firebase'), findsOneWidget);

    await tester.tap(find.text('جرّب ببيانات تجريبية'));
    await tester.pumpAndSettle();
    expect(find.text('لوحة التحكم'), findsOneWidget);
    expect(find.text('نشط اليوم'), findsOneWidget);

    await tester.tap(find.text('تواصل').first);
    await tester.pumpAndSettle();
    expect(find.text('شهد العتيبي'), findsOneWidget);

    await tester.tap(find.text('شهد العتيبي'));
    await tester.pumpAndSettle();
    expect(find.text('حظر دائم'), findsOneWidget);
    expect(find.text('تسجيل خروج إجباري'), findsOneWidget);

    await tester.tap(find.text('المحتوى'));
    await tester.pumpAndSettle();
    expect(find.text('القصص'), findsOneWidget);
  });
}
