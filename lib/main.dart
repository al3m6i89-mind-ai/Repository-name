import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'backend/session.dart';
import 'screens/start_screens.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final session = HubSession();
  final theme = ThemeController();
  await theme.load();
  runApp(AdminHubApp(session: session, theme: theme));
}

class ThemeController extends ChangeNotifier {
  ThemeMode mode = ThemeMode.system;

  Future<void> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      mode = ThemeMode.values.byName(p.getString('themeMode') ?? 'system');
    } catch (_) {}
  }

  Future<void> set(ThemeMode m) async {
    mode = m;
    notifyListeners();
    try {
      (await SharedPreferences.getInstance()).setString('themeMode', m.name);
    } catch (_) {}
  }
}

/// Gives every screen the session and theme without passing them around.
class Hub extends InheritedWidget {
  final HubSession session;
  final ThemeController theme;
  const Hub({super.key, required this.session, required this.theme, required super.child});

  static Hub of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<Hub>()!;

  @override
  bool updateShouldNotify(Hub old) => false;
}

class AdminHubApp extends StatelessWidget {
  final HubSession session;
  final ThemeController theme;
  const AdminHubApp({super.key, required this.session, required this.theme});

  @override
  Widget build(BuildContext context) {
    return Hub(
      session: session,
      theme: theme,
      child: ListenableBuilder(
        listenable: theme,
        builder: (_, __) => MaterialApp(
          title: 'لوحة تطبيقاتي',
          debugShowCheckedModeBanner: false,
          locale: const Locale('ar'),
          supportedLocales: const [Locale('ar'), Locale('en')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          theme: buildTheme(Brightness.light),
          darkTheme: buildTheme(Brightness.dark),
          themeMode: theme.mode,
          home: const StartScreen(),
        ),
      ),
    );
  }
}
