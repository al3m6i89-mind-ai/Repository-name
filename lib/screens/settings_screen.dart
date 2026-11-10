import 'package:flutter/material.dart';

import '../backend/session.dart';
import '../main.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'setup_guide_screen.dart';
import 'start_screens.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final hub = Hub.of(context);
    final s = hub.session;
    return Scaffold(
      appBar: AppBar(title: const Text('الإعدادات')),
      body: ListenableBuilder(
        listenable: Listenable.merge([s, hub.theme]),
        builder: (context, _) => ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 32), children: [
          const SectionTitle('الحسابات المربوطة'),
          Card(
            child: Column(children: [
              for (final l in s.linked)
                ListTile(
                  leading: Text(l.connection.icon, style: const TextStyle(fontSize: 24)),
                  title: Text(l.connection.label, style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text(l.ok ? l.connection.typeLabel : 'غير متصل: ${l.error}', maxLines: 2, overflow: TextOverflow.ellipsis),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(l.ok ? Icons.check_circle_rounded : Icons.error_rounded, color: l.ok ? Brand.success : Brand.danger),
                    IconButton(
                      tooltip: 'فصل الحساب',
                      icon: const Icon(Icons.delete_outline_rounded),
                      onPressed: () async {
                        final ok = await confirm(context, 'فصل ${l.connection.label}؟',
                            'يُحذف الحساب من هذا الجهاز فقط. ما يتأثر شي في Firebase.', action: 'فصل');
                        if (!ok) return;
                        await s.remove(l);
                        if (context.mounted) toast(context, 'تم فصل ${l.connection.label}');
                      },
                    ),
                  ]),
                ),
              ListTile(
                leading: const Icon(Icons.add_link_rounded),
                title: const Text('ربط حساب Firebase جديد'),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AddConnectionScreen())),
              ),
              if (!s.linked.any((l) => l.connection.type == ConnectionType.demo))
                ListTile(
                  leading: const Icon(Icons.science_outlined),
                  title: const Text('إضافة البيانات التجريبية'),
                  onTap: () => s.add(Connection(id: 'demo', type: ConnectionType.demo, label: 'تجريبي', icon: '🧪')),
                ),
            ]),
          ),
          const SectionTitle('المظهر'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: SegmentedButton<ThemeMode>(
                segments: const [
                  ButtonSegment(value: ThemeMode.system, label: Text('تلقائي'), icon: Icon(Icons.brightness_auto_outlined)),
                  ButtonSegment(value: ThemeMode.light, label: Text('فاتح'), icon: Icon(Icons.light_mode_outlined)),
                  ButtonSegment(value: ThemeMode.dark, label: Text('داكن'), icon: Icon(Icons.dark_mode_outlined)),
                ],
                selected: {hub.theme.mode},
                onSelectionChanged: (v) => hub.theme.set(v.first),
              ),
            ),
          ),
          const SectionTitle('الأمان'),
          Card(
            child: Column(children: [
              ListTile(
                leading: const Icon(Icons.lock_outline_rounded),
                title: Text(s.lockHash.isEmpty ? 'قفل اللوحة بكلمة مرور' : 'تغيير كلمة مرور اللوحة'),
                subtitle: const Text('تُطلب كل ما تفتح التطبيق'),
                onTap: () async {
                  final p = await askText(context, 'كلمة مرور اللوحة', label: '4 أحرف أو أكثر');
                  if (p == null) return;
                  if (p.length < 4) {
                    if (context.mounted) toast(context, 'كلمة المرور قصيرة', error: true);
                    return;
                  }
                  await s.setLock(p);
                  if (context.mounted) toast(context, 'تم قفل اللوحة');
                },
              ),
              if (s.lockHash.isNotEmpty)
                ListTile(
                  leading: const Icon(Icons.lock_open_rounded),
                  title: const Text('إلغاء القفل'),
                  onTap: () async {
                    await s.setLock('');
                    if (context.mounted) toast(context, 'تم إلغاء القفل');
                  },
                ),
            ]),
          ),
          const SectionTitle('المساعدة'),
          Card(
            child: Column(children: [
              ListTile(
                leading: const Icon(Icons.menu_book_outlined),
                title: const Text('شرح الإعداد خطوة بخطوة'),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SetupGuideScreen())),
              ),
              const ListTile(
                leading: Icon(Icons.info_outline_rounded),
                title: Text('لوحة تطبيقاتي'),
                subtitle: Text('الإصدار 2.0'),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}
