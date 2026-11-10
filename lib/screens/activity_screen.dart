import 'package:flutter/material.dart';

import '../backend/actions.dart';
import '../backend/models.dart';
import '../main.dart';
import '../ui/widgets.dart';

/// Every admin action across all accounts, newest first.
class ActivityScreen extends StatefulWidget {
  const ActivityScreen({super.key});

  @override
  State<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends State<ActivityScreen> {
  Future<List<(AppInfo, LogEntry)>>? _logs;
  String? _app;
  String _q = '';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _logs ??= Hub.of(context).session.allLogs();
  }

  void _reload() => setState(() => _logs = Hub.of(context).session.allLogs());

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('سجل الإجراءات'),
        actions: [IconButton(onPressed: _reload, icon: const Icon(Icons.refresh_rounded), tooltip: 'تحديث')],
      ),
      body: FutureBuilder<List<(AppInfo, LogEntry)>>(
        future: _logs,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
          if (snap.hasError) return ErrorView(message: '${snap.error}', onRetry: _reload);
          final all = snap.data!;
          if (all.isEmpty) {
            return const EmptyView(
              icon: Icons.history_rounded,
              title: 'السجل فاضي',
              text: 'كل إجراء تسويه على مستخدم (حظر، حجب، رسالة…) يظهر هنا مع الوقت.',
            );
          }
          final apps = {for (final e in all) e.$1.key: e.$1};
          final q = _q.trim().toLowerCase();
          final shown = all
              .where((e) => _app == null || e.$1.key == _app)
              .where((e) => q.isEmpty || '${e.$2.userName} ${e.$2.action} ${e.$2.detail}'.toLowerCase().contains(q))
              .toList();
          String? lastDay;
          return RefreshIndicator(
            onRefresh: () async => _reload(),
            child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), children: [
              TextField(
                decoration: const InputDecoration(prefixIcon: Icon(Icons.search_rounded), hintText: 'ابحث في السجل'),
                onChanged: (v) => setState(() => _q = v),
              ),
              const SizedBox(height: 10),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: [
                  ChoiceChip(label: const Text('كل التطبيقات'), selected: _app == null, onSelected: (_) => setState(() => _app = null)),
                  for (final a in apps.values) ...[
                    const SizedBox(width: 8),
                    ChoiceChip(label: Text('${a.icon} ${a.name}'), selected: _app == a.key, onSelected: (_) => setState(() => _app = a.key)),
                  ],
                ]),
              ),
              for (final e in shown) ...[
                if (fmtDate(e.$2.at) != lastDay) ...[
                  Builder(builder: (_) {
                    lastDay = fmtDate(e.$2.at);
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(4, 18, 4, 8),
                      child: Text(lastDay!, style: TextStyle(color: cs.onSurfaceVariant, fontWeight: FontWeight.w700)),
                    );
                  }),
                ],
                Card(
                  child: ListTile(
                    leading: CircleAvatar(backgroundColor: cs.primaryContainer, child: Text(e.$1.icon)),
                    title: Text('${e.$2.action} · ${e.$2.userName}', style: const TextStyle(fontWeight: FontWeight.w800)),
                    subtitle: Text(
                      [if (e.$2.detail.isNotEmpty) e.$2.detail, '${e.$1.name} · ${fmtDateTime(e.$2.at)}', if (e.$2.by.isNotEmpty) 'بواسطة ${e.$2.by}']
                          .join('\n'),
                      style: const TextStyle(height: 1.5),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ]),
          );
        },
      ),
    );
  }
}
