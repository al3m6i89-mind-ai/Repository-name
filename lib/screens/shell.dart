import 'package:flutter/material.dart';

import 'activity_screen.dart';
import 'apps_screen.dart';
import 'dashboard_screen.dart';
import 'settings_screen.dart';

/// Bottom bar on phones, side rail on wide screens.
class Shell extends StatefulWidget {
  const Shell({super.key});

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int _i = 0;

  static const _dest = [
    (Icons.space_dashboard_outlined, Icons.space_dashboard_rounded, 'الرئيسية'),
    (Icons.apps_outlined, Icons.apps_rounded, 'التطبيقات'),
    (Icons.history_outlined, Icons.history_rounded, 'السجل'),
    (Icons.settings_outlined, Icons.settings_rounded, 'الإعدادات'),
  ];

  void go(int i) => setState(() => _i = i);

  @override
  Widget build(BuildContext context) {
    final pages = [
      DashboardScreen(onOpenApps: () => go(1), onOpenLog: () => go(2)),
      const AppsScreen(),
      const ActivityScreen(),
      const SettingsScreen(),
    ];
    final wide = MediaQuery.of(context).size.width >= 900;
    final body = IndexedStack(index: _i, children: pages);
    if (wide) {
      return Scaffold(
        body: Row(children: [
          NavigationRail(
            selectedIndex: _i,
            onDestinationSelected: go,
            labelType: NavigationRailLabelType.all,
            leading: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.asset('assets/branding/icon.png', width: 44, height: 44),
              ),
            ),
            destinations: [
              for (final d in _dest) NavigationRailDestination(icon: Icon(d.$1), selectedIcon: Icon(d.$2), label: Text(d.$3)),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(child: body),
        ]),
      );
    }
    return Scaffold(
      body: body,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _i,
        onDestinationSelected: go,
        destinations: [for (final d in _dest) NavigationDestination(icon: Icon(d.$1), selectedIcon: Icon(d.$2), label: d.$3)],
      ),
    );
  }
}
