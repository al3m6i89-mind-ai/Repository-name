import 'package:flutter/material.dart';

import '../backend/actions.dart';
import '../backend/models.dart';
import '../main.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'user_detail_screen.dart';
import 'users_screen.dart';

class _AppStats {
  final AppInfo app;
  final List<AppUser> users;
  final String? error;
  _AppStats(this.app, this.users, [this.error]);
}

class DashboardScreen extends StatefulWidget {
  final VoidCallback onOpenApps;
  final VoidCallback onOpenLog;
  const DashboardScreen({super.key, required this.onOpenApps, required this.onOpenLog});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  Future<(List<_AppStats>, List<(AppInfo, LogEntry)>)>? _data;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _data ??= _load();
  }

  Future<(List<_AppStats>, List<(AppInfo, LogEntry)>)> _load() async {
    final s = Hub.of(context).session;
    final apps = await s.allApps();
    final stats = await Future.wait(apps.map((a) async {
      try {
        return _AppStats(a, await s.backendOf(a).listUsers(a.id));
      } catch (e) {
        return _AppStats(a, const [], '$e');
      }
    }));
    final logs = await s.allLogs(limit: 6);
    return (stats, logs);
  }

  Future<void> _reload() async {
    final f = _load();
    setState(() => _data = f);
    await f;
  }

  @override
  Widget build(BuildContext context) {
    final session = Hub.of(context).session;
    return ListenableBuilder(
      listenable: session,
      builder: (context, _) => Scaffold(
        body: RefreshIndicator(
          onRefresh: _reload,
          child: FutureBuilder(
            future: _data,
            builder: (context, snap) {
              final data = snap.data;
              return CustomScrollView(slivers: [
                SliverToBoxAdapter(child: _header(context, data?.$1)),
                if (data == null)
                  const SliverFillRemaining(child: Center(child: CircularProgressIndicator()))
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    sliver: SliverList.list(children: _body(context, data.$1, data.$2)),
                  ),
              ]);
            },
          ),
        ),
      ),
    );
  }

  Widget _header(BuildContext context, List<_AppStats>? stats) {
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
          const Expanded(
            child: Text('لوحة التحكم', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800)),
          ),
          IconButton(
            onPressed: _reload,
            icon: const Icon(Icons.refresh_rounded, color: Colors.white),
            tooltip: 'تحديث',
          ),
        ]),
        const SizedBox(height: 4),
        Text(
          '${s.linked.length} حساب مربوط${broken > 0 ? ' · $broken يحتاج انتباه' : ''}',
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
          Text(v, style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w800)),
          Text(l, style: const TextStyle(color: Colors.white70, fontSize: 13)),
        ]),
      );

  List<Widget> _body(BuildContext context, List<_AppStats> stats, List<(AppInfo, LogEntry)> logs) {
    final cs = Theme.of(context).colorScheme;
    final all = [for (final a in stats) for (final u in a.users) (a.app, u)];
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
      for (final a in stats) ...[
        Card(
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => UsersScreen(app: a.app)))
                .then((_) => _reload()),
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
                          style: TextStyle(color: a.error != null ? Brand.danger : cs.onSurfaceVariant, fontSize: 13)),
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
                    .push(MaterialPageRoute(builder: (_) => UserDetailScreen(app: p.$1, user: p.$2)))
                    .then((_) => _reload()),
              ),
          ]),
        ),
      ],
      if (logs.isNotEmpty) ...[
        SectionTitle('آخر الإجراءات', trailing: TextButton(onPressed: widget.onOpenLog, child: const Text('السجل كامل'))),
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
