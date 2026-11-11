import 'package:flutter/material.dart';

import '../backend/actions.dart';
import '../backend/models.dart';
import '../main.dart';
import '../ui/action_dialogs.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'user_detail_screen.dart';

enum _Sort { lastSeen, newest, name }

class UsersScreen extends StatefulWidget {
  final AppInfo app;
  const UsersScreen({super.key, required this.app});

  @override
  State<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends State<UsersScreen> {
  List<AppUser>? get _users {
    final d = Hub.of(context).session.dataOf(widget.app);
    return d == null || (d.users.isEmpty && d.updated == null) ? null : d.users;
  }

  Object? get _error {
    final d = Hub.of(context).session.dataOf(widget.app);
    return d?.users.isEmpty == true ? d?.error : null;
  }

  bool _started = false;
  String _query = '';
  UserStatus? _filter;
  _Sort _sort = _Sort.lastSeen;
  final Set<String> _selected = {};
  bool _busy = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started) {
      _started = true;
      // Show what is cached now, refresh quietly.
      Future.microtask(_load);
    }
  }

  Future<void> _load() => Hub.of(context).session.refreshApp(widget.app);

  List<AppUser> _shown() {
    final q = _query.trim().toLowerCase();
    final list = (_users ?? const <AppUser>[])
        .where((u) => _filter == null || u.status == _filter)
        .where((u) =>
            q.isEmpty ||
            u.name.toLowerCase().contains(q) ||
            u.email.toLowerCase().contains(q) ||
            u.phone.contains(q) ||
            u.id.toLowerCase().contains(q))
        .toList();
    switch (_sort) {
      case _Sort.lastSeen:
        list.sort((a, b) => (b.lastSeen ?? DateTime(0)).compareTo(a.lastSeen ?? DateTime(0)));
      case _Sort.newest:
        list.sort((a, b) => (b.createdAt ?? DateTime(0)).compareTo(a.createdAt ?? DateTime(0)));
      case _Sort.name:
        list.sort((a, b) => a.displayName.compareTo(b.displayName));
    }
    return list;
  }

  Future<void> _bulk(String what) async {
    final targets = _users!.where((u) => _selected.contains(u.id)).toList();
    if (targets.isEmpty) return;
    final acts = UserActions(Hub.of(context).session.backendOf(widget.app));
    final appId = widget.app.id;
    Future<void> Function(AppUser)? run;
    switch (what) {
      case 'ban':
        final r = await askText(context, 'حظر ${targets.length} مستخدم', label: 'السبب (اختياري)');
        if (r != null) run = (u) => acts.ban(appId, u, r);
      case 'suspend':
        final d = await pickDuration(context);
        if (d != null && mounted) {
          final r = await askText(context, 'حجب ${durationLabel(d)}', label: 'السبب (اختياري)');
          if (r != null) run = (u) => acts.suspend(appId, u, DateTime.now().add(d), r);
        }
      case 'message':
        final m = await askText(context, 'رسالة لـ ${targets.length} مستخدم',
            label: 'نص الرسالة', required: true, maxLines: 4);
        if (m != null) run = (u) => acts.message(appId, u, m).then((_) {});
      case 'logout':
        if (await confirm(context, 'تسجيل خروج ${targets.length} مستخدم؟', 'يخرجون من كل الأجهزة ويلزمهم دخول من جديد.',
            danger: false)) {
          run = (u) => acts.forceLogout(appId, u);
        }
      case 'unban':
        run = (u) async {
          if (u.banned) await acts.unban(appId, u);
          if (u.status == UserStatus.suspended) await acts.unsuspend(appId, u);
        };
      case 'delete':
        if (await confirm(context, 'حذف ${targets.length} حساب نهائياً؟', 'ما تقدر ترجعهم بعد الحذف.',
            action: 'حذف نهائي')) {
          run = (u) => acts.delete(appId, u);
        }
    }
    if (run == null || !mounted) return;
    setState(() => _busy = true);
    var failed = 0;
    for (final u in targets) {
      try {
        await run(u);
      } catch (_) {
        failed++;
      }
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _selected.clear();
    });
    _load();
    toast(
        context, failed == 0 ? 'تم تنفيذ الإجراء على ${targets.length}' : 'نجح ${targets.length - failed} وفشل $failed',
        error: failed > 0);
  }

  @override
  Widget build(BuildContext context) {
    final selecting = _selected.isNotEmpty;
    return Scaffold(
      appBar: selecting
          ? AppBar(
              leading: IconButton(icon: const Icon(Icons.close), onPressed: () => setState(_selected.clear)),
              title: Text('${_selected.length} محدد'),
              actions: [
                IconButton(
                  tooltip: 'تحديد الكل',
                  icon: const Icon(Icons.select_all_rounded),
                  onPressed: () => setState(() => _selected.addAll(_shown().map((u) => u.id))),
                ),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert),
                  onSelected: _bulk,
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'message', child: Text('إرسال رسالة')),
                    PopupMenuItem(value: 'suspend', child: Text('حجب مؤقت')),
                    PopupMenuItem(value: 'ban', child: Text('حظر')),
                    PopupMenuItem(value: 'unban', child: Text('فك الحظر والحجب')),
                    PopupMenuItem(value: 'logout', child: Text('تسجيل خروج إجباري')),
                    PopupMenuItem(value: 'delete', child: Text('حذف الحسابات', style: TextStyle(color: Brand.danger))),
                  ],
                ),
              ],
            )
          : AppBar(
              title: Row(children: [
                AppBadge(app: widget.app, size: 34),
                const SizedBox(width: 10),
                Flexible(child: Text(widget.app.name, overflow: TextOverflow.ellipsis)),
              ]),
              actions: [
                PopupMenuButton<_Sort>(
                  icon: const Icon(Icons.sort_rounded),
                  tooltip: 'ترتيب',
                  onSelected: (s) => setState(() => _sort = s),
                  itemBuilder: (_) => [
                    CheckedPopupMenuItem(
                        value: _Sort.lastSeen, checked: _sort == _Sort.lastSeen, child: const Text('آخر ظهور')),
                    CheckedPopupMenuItem(
                        value: _Sort.newest, checked: _sort == _Sort.newest, child: const Text('الأحدث تسجيلاً')),
                    CheckedPopupMenuItem(value: _Sort.name, checked: _sort == _Sort.name, child: const Text('الاسم')),
                  ],
                ),
                IconButton(onPressed: _load, icon: const Icon(Icons.refresh_rounded), tooltip: 'تحديث'),
              ],
            ),
      body: ListenableBuilder(
        listenable: Hub.of(context).session,
        builder: (context, _) => Column(children: [
          if (_busy) const LinearProgressIndicator(),
          Expanded(
            child: _error != null
                ? ErrorView(message: '$_error', onRetry: _load)
                : _users == null
                    ? const Padding(padding: EdgeInsets.all(16), child: SkeletonList())
                    : _list(),
          ),
        ]),
      ),
    );
  }

  Widget _list() {
    final users = _users!;
    final shown = _shown();
    int count(UserStatus s) => users.where((u) => u.status == s).length;
    final header = <Widget>[
      TextField(
        decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search_rounded), hintText: 'ابحث بالاسم أو الإيميل أو الجوال أو المعرّف'),
        onChanged: (v) => setState(() => _query = v),
      ),
      const SizedBox(height: 12),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          ChoiceChip(
              label: Text('الكل ${users.length}'),
              selected: _filter == null,
              onSelected: (_) => setState(() => _filter = null)),
          for (final s in UserStatus.values) ...[
            const SizedBox(width: 8),
            ChoiceChip(
              label: Text('${statusName(s)} ${count(s)}'),
              selected: _filter == s,
              onSelected: (_) => setState(() => _filter = _filter == s ? null : s),
            ),
          ],
        ]),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
        child: Text('${shown.length} نتيجة · اضغط مطولاً لتحديد أكثر من واحد',
            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12)),
      ),
      if (shown.isEmpty)
        const Padding(
            padding: EdgeInsets.only(top: 50),
            child: EmptyView(icon: Icons.people_outline_rounded, title: 'ما فيه مستخدمين هنا')),
    ];
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        itemCount: header.length + shown.length,
        itemBuilder: (_, i) => i < header.length
            ? header[i]
            : Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Appear(index: i - header.length, child: _tile(shown[i - header.length])),
              ),
      ),
    );
  }

  Widget _tile(AppUser u) {
    final cs = Theme.of(context).colorScheme;
    final sel = _selected.contains(u.id);
    void toggle() => setState(() => sel ? _selected.remove(u.id) : _selected.add(u.id));
    return Card(
      clipBehavior: Clip.antiAlias,
      color: sel ? cs.primaryContainer.withValues(alpha: .5) : null,
      child: InkWell(
        onLongPress: toggle,
        onTap: _selected.isNotEmpty
            ? toggle
            : () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => UserDetailScreen(app: widget.app, user: u))),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            sel
                ? Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(color: cs.primary, borderRadius: BorderRadius.circular(15)),
                    child: const Icon(Icons.check_rounded, color: Colors.white),
                  )
                : UserAvatar(user: u, size: 46, heroTag: 'av-${widget.app.key}-${u.id}'),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Flexible(
                    child: Text(u.displayName,
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                        overflow: TextOverflow.ellipsis),
                  ),
                  if (u.verified)
                    const Padding(
                        padding: EdgeInsetsDirectional.only(start: 4),
                        child: Icon(Icons.verified_rounded, size: 16, color: Brand.info)),
                ]),
                const SizedBox(height: 2),
                Text(u.email.isNotEmpty ? u.email : (u.phone.isNotEmpty ? u.phone : u.id),
                    style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13), overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  Text('آخر ظهور ${fmtAgo(u.lastSeen)}', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
                  if (u.role != 'user') Pill(userRoles[u.role] ?? u.role, color: Brand.violet),
                ]),
              ]),
            ),
            const SizedBox(width: 8),
            ConstrainedBox(constraints: const BoxConstraints(maxWidth: 120), child: StatusPill(user: u)),
          ]),
        ),
      ),
    );
  }
}
