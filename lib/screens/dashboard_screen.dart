import 'package:flutter/material.dart';

import '../backend/actions.dart';
import '../backend/models.dart';
import '../backend/session.dart';
import '../main.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'user_detail_screen.dart';
import 'users_screen.dart';

class DashboardScreen extends StatefulWidget {
  final VoidCallback onOpenApps;
  final VoidCallback onOpenLog;
  final VoidCallback? onOpenAssistant;
  const DashboardScreen({super.key, required this.onOpenApps, required this.onOpenLog, this.onOpenAssistant});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  List<(AppInfo, LogEntry)> _logs = const [];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final s = Hub.of(context).session;
    s.ready.then((_) => _loadLogs());
  }

  Future<void> _loadLogs() async {
    final logs = await Hub.of(context).session.allLogs(limit: 6);
    if (mounted) setState(() => _logs = logs);
  }

  Future<void> _reload() async {
    final s = Hub.of(context).session;
    await s.refreshAll();
    await _loadLogs();
  }

  void _openApp(AppInfo app) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => UsersScreen(app: app)));

  @override
  Widget build(BuildContext context) {
    final session = Hub.of(context).session;
    return ListenableBuilder(
      listenable: session,
      builder: (context, _) {
        final stats = session.apps;
        final loading = stats.isEmpty && (session.refreshing || session.linked.any((l) => l.connecting));
        return Scaffold(
          floatingActionButton: widget.onOpenAssistant == null
              ? null
              : FloatingActionButton.extended(
                  heroTag: 'assistant',
                  onPressed: widget.onOpenAssistant,
                  icon: const Icon(Icons.auto_awesome_rounded),
                  label: const Text('اسأل المساعد'),
                ),
          body: RefreshIndicator(
            onRefresh: _reload,
            child: CustomScrollView(slivers: [
              SliverToBoxAdapter(child: _header(context, loading ? null : stats)),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
                sliver: SliverList.list(children: loading ? _skeleton() : _body(context, stats, _logs)),
              ),
            ]),
          ),
        );
      },
    );
  }

  List<Widget> _skeleton() => [
        const SizedBox(height: 20),
        const Skeleton(height: 18, width: 110),
        const SizedBox(height: 14),
        Row(children: [
          for (var i = 0; i < 3; i++) ...[
            if (i > 0) const SizedBox(width: 10),
            const Expanded(child: Skeleton(height: 110, radius: 18)),
          ],
        ]),
        const SizedBox(height: 20),
        const SkeletonList(count: 3),
      ];

  Widget _header(BuildContext context, List<AppData>? stats) {
    final s = Hub.of(context).session;
    final total = stats?.fold<int>(0, (n, a) => n + a.users.length);
    final online = stats?.fold<int>(0, (n, a) => n + a.users.where((u) => u.onlineRecently).length);
    final broken = s.linked.where((l) => !l.ok).length;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 4),
      padding: EdgeInsets.fromLTRB(20, MediaQuery.of(context).padding.top + 18, 20, 22),
      decoration: const BoxDecoration(
        gradient: Brand.gradient,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_greeting(), style: const TextStyle(color: Colors.white70, fontSize: 14)),
              const Text('لوحة التحكم', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800)),
            ]),
          ),
          if (s.refreshing)
            const Padding(
              padding: EdgeInsets.all(12),
              child: SizedBox(
                  width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
            )
          else
            IconButton(
              onPressed: _reload,
              icon: const Icon(Icons.refresh_rounded, color: Colors.white),
              tooltip: 'تحديث',
            ),
        ]),
        const SizedBox(height: 4),
        Text(
          [
            '${s.linked.length} حساب مربوط',
            if (broken > 0) '$broken يحتاج انتباه',
            if (s.lastRefresh != null) 'آخر تحديث ${fmtAgo(s.lastRefresh)}',
          ].join(' · '),
          style: const TextStyle(color: Colors.white70),
        ),
        const SizedBox(height: 18),
        Row(children: [
          _heroNum('${total ?? '…'}', 'مستخدم'),
          _heroNum('${online ?? '…'}', 'متصل الآن'),
          _heroNum('${stats?.length ?? '…'}', 'تطبيق'),
        ]),
      ]),
    );
  }

  Widget _heroNum(String v, String l) => Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          int.tryParse(v) != null
              ? CountUp(int.parse(v),
                  style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w800))
              : Text(v, style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w800)),
          Text(l, style: const TextStyle(color: Colors.white70, fontSize: 13)),
        ]),
      );

  List<Widget> _body(BuildContext context, List<AppData> stats, List<(AppInfo, LogEntry)> logs) {
    final cs = Theme.of(context).colorScheme;
    final all = [
      for (final a in stats)
        for (final u in a.users) (a.app, u)
    ];
    final now = DateTime.now();
    int count(bool Function(AppUser) f) => all.where((p) => f(p.$2)).length;
    final today = count((u) => u.lastSeen != null && now.difference(u.lastSeen!).inHours < 24);
    final week = count((u) => u.createdAt != null && now.difference(u.createdAt!).inDays < 7);
    final banned = count((u) => u.status == UserStatus.banned);
    final suspended = count((u) => u.status == UserStatus.suspended);
    final restricted = count((u) => u.status == UserStatus.restricted);
    final verified = count((u) => u.verified);
    final cols = MediaQuery.of(context).size.width >= 900 ? 6 : 3;

    final recent = [...all]..sort((a, b) => (b.$2.createdAt ?? DateTime(0)).compareTo(a.$2.createdAt ?? DateTime(0)));

    if (stats.isEmpty) {
      return [
        const SizedBox(height: 40),
        EmptyView(
          icon: Icons.apps_rounded,
          title: 'ما فيه تطبيقات بعد',
          text: 'اربط حساب Firebase من صفحة التطبيقات.',
          action: FilledButton(onPressed: widget.onOpenApps, child: const Text('إلى التطبيقات')),
        ),
      ];
    }

    return [
      const SectionTitle('نظرة عامة'),
      GridView(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: cols,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          mainAxisExtent: 124 * MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.6),
        ),
        children: [
          StatCard(label: 'نشط اليوم', value: '$today', icon: Icons.bolt_rounded, color: Brand.success),
          StatCard(label: 'جدد هذا الأسبوع', value: '$week', icon: Icons.person_add_alt_1_rounded, color: Brand.info),
          StatCard(label: 'موثّق', value: '$verified', icon: Icons.verified_rounded, color: Brand.primary),
          StatCard(label: 'محظور', value: '$banned', icon: Icons.block_rounded, color: Brand.danger),
          StatCard(label: 'محجوب مؤقتاً', value: '$suspended', icon: Icons.timer_outlined, color: Brand.warning),
          StatCard(label: 'مقيّد', value: '$restricted', icon: Icons.tune_rounded, color: Brand.violet),
        ],
      ),
      SectionTitle('التطبيقات', trailing: TextButton(onPressed: widget.onOpenApps, child: const Text('عرض الكل'))),
      for (final (i, a) in stats.indexed) ...[
        Appear(
          index: i,
          child: Card(
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => _openApp(a.app),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(children: [
                  Row(children: [
                    AppBadge(app: a.app, size: 44),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(a.app.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                        Text(a.error != null ? 'تعذّر التحميل' : '${a.users.length} مستخدم',
                            style:
                                TextStyle(color: a.error != null ? Brand.danger : cs.onSurfaceVariant, fontSize: 13)),
                      ]),
                    ),
                    const Icon(Icons.chevron_left_rounded),
                  ]),
                  if (a.users.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    _StatusBar(users: a.users),
                  ],
                ]),
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
      ],
      if (recent.isNotEmpty) ...[
        const SectionTitle('أحدث المسجلين'),
        Card(
          child: Column(children: [
            for (final p in recent.take(5))
              ListTile(
                leading: UserAvatar(user: p.$2, size: 40),
                title: Text(p.$2.displayName, style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text('${p.$1.icon} ${p.$1.name} · ${fmtAgo(p.$2.createdAt)}'),
                trailing: StatusPill(user: p.$2),
                onTap: () => Navigator.of(context)
                    .push(MaterialPageRoute(builder: (_) => UserDetailScreen(app: p.$1, user: p.$2))),
              ),
          ]),
        ),
      ],
      if (logs.isNotEmpty) ...[
        SectionTitle('آخر الإجراءات',
            trailing: TextButton(onPressed: widget.onOpenLog, child: const Text('السجل كامل'))),
        Card(
          child: Column(children: [
            for (final l in logs)
              ListTile(
                dense: true,
                leading: CircleAvatar(radius: 18, backgroundColor: cs.primaryContainer, child: Text(l.$1.icon)),
                title: Text('${l.$2.action} · ${l.$2.userName}', style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(fmtAgo(l.$2.at)),
              ),
          ]),
        ),
      ],
    ];
  }
}

/// Coloured bar showing how an app's users split by status.
class _StatusBar extends StatelessWidget {
  final List<AppUser> users;
  const _StatusBar({required this.users});

  @override
  Widget build(BuildContext context) {
    final counts = {for (final s in UserStatus.values) s: users.where((u) => u.status == s).length};
    const colors = {
      UserStatus.active: Brand.success,
      UserStatus.restricted: Brand.info,
      UserStatus.suspended: Brand.warning,
      UserStatus.banned: Brand.danger,
    };
    return Column(children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: SizedBox(
          height: 8,
          child: Row(children: [
            for (final s in UserStatus.values)
              if (counts[s]! > 0) Expanded(flex: counts[s]!, child: Container(color: colors[s])),
          ]),
        ),
      ),
      const SizedBox(height: 8),
      Wrap(spacing: 14, runSpacing: 4, children: [
        for (final s in UserStatus.values)
          if (counts[s]! > 0)
            Row(mainAxisSize: MainAxisSize.min, children: [
              Container(width: 8, height: 8, decoration: BoxDecoration(color: colors[s], shape: BoxShape.circle)),
              const SizedBox(width: 5),
              Text('${statusName(s)} ${counts[s]}', style: const TextStyle(fontSize: 12)),
            ]),
      ]),
    ]);
  }
}

String _greeting() {
  final h = DateTime.now().hour;
  if (h < 5) return 'سهرانين؟ 🌙';
  if (h < 12) return 'صباح الخير ☀️';
  if (h < 17) return 'يومك سعيد 🌤️';
  return 'مساء الخير 🌙';
}
