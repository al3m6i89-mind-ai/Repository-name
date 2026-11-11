import 'package:admin_hub/backend/session.dart';
import 'package:admin_hub/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  for (final (w, scale) in [(412.0, 1.0), (360.0, 1.3)]) {
    testWidgets('demo flow at ${w}dp, text x$scale', (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = Size(w * 3, 2400);
      tester.view.devicePixelRatio = 3;
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      await tester.pumpWidget(AdminHubApp(session: HubSession(), theme: ThemeController()));
      await tester.pumpAndSettle();
      expect(find.text('ربط حساب Firebase'), findsOneWidget);

      await tester.ensureVisible(find.text('جرّب ببيانات تجريبية'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('جرّب ببيانات تجريبية'));
      await tester.pumpAndSettle();
      expect(find.text('لوحة التحكم'), findsOneWidget);
      expect(find.text('نشط اليوم'), findsOneWidget);

      await tester.tap(find.text('المساعد').last);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'كم واحد محظور؟');
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await tester.pump();
      expect(find.textContaining('محظور.'), findsOneWidget);

      await tester.tap(find.text('التطبيقات').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('تواصل').first);
      await tester.pumpAndSettle();
      expect(find.text('شهد العتيبي'), findsOneWidget);

      await tester.tap(find.text('شهد العتيبي'));
      await tester.pumpAndSettle();
      expect(find.text('حظر دائم'), findsOneWidget);

      await tester.tap(find.text('المحتوى'));
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(find.text('القصص'), findsOneWidget);

      await tester.tap(find.text('الحساب'));
      await tester.pumpAndSettle();
      expect(find.text('معلومات الحساب'), findsOneWidget);
    });
  }
}
