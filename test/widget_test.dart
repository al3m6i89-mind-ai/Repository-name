import 'package:admin_hub/config.dart';
import 'package:admin_hub/main.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('demo login opens apps, then users', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(AdminHubApp(config: HubConfig()));
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.6;
    addTearDown(tester.view.reset);
    await tester.tap(find.text('عبّئ'));
    await tester.pump();
    await tester.ensureVisible(find.text('دخول'));
    await tester.tap(find.text('دخول'));
    await tester.pumpAndSettle();
    expect(find.text('تطبيقاتي'), findsOneWidget);
    expect(find.text('متجري'), findsOneWidget);
    await tester.tap(find.text('متجري'));
    await tester.pumpAndSettle();
    expect(find.text('أحمد علي'), findsOneWidget);
    expect(find.textContaining('محظور'), findsWidgets);
  });
}
