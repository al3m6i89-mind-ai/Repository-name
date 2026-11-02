import 'package:flutter/material.dart';

import '../backend/backend.dart';
import '../backend/models.dart';
import 'apps_screen.dart' show ErrorView, EmptyView, confirm;

String fmtDate(DateTime? d) {
  if (d == null) return '—';
  String two(int n) => n.toString().padLeft(2, '0');
  return '${d.year}/${two(d.month)}/${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
}

String fmtLeft(DateTime until) {
  final left = until.difference(DateTime.now());
  if (left.inDays >= 1) return '${left.inDays} يوم';
  if (left.inHours >= 1) return '${left.inHours} ساعة';
  return '${left.inMinutes.clamp(1, 59)} دقيقة';
}

class UsersScreen extends StatefulWidget {
  final AdminBackend backend;
  final AppInfo app;
  const UsersScreen({super.key, required this.backend, required this.app});

  @override
  State<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends State<UsersScreen> {
  List<AppUser>? _users;
  Object? _error;
  String _query = '';
  UserStatus? _filter;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final users = await widget.backend.listUsers(widget.app.id);
      users.sort((a, b) => (b.lastSeen ?? DateTime(0)).compareTo(a.lastSeen ?? DateTime(0)));
      if (mounted) setState(() => _users = users);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final users = _users;
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.app.icon} ${widget.app.name}'),
        actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh), tooltip: 'تحديث')],
      ),
      body: _error != null
          ? ErrorView(message: '$_error', onRetry: _load)
          : users == null
              ? const Center(child: CircularProgressIndicator())
              : _body(users),
    );
  }

  Widget _body(List<AppUser> users) {
    int count(UserStatus s) => users.where((u) => u.status == s).length;
    final q = _query.trim().toLowerCase();
    final shown = users
        .where((u) => _filter == null || u.status == _filter)
        .where((u) => q.isEmpty || u.name.toLowerCase().contains(q) || u.email.toLowerCase().contains(q) || u.id.contains(q))
        .toList();

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
        children: [
          TextField(
            decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'ابحث بالاسم أو الإيميل'),
            onChanged: (v) => setState(() => _query = v),
          ),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 4, children: [
            ChoiceChip(label: Text('الكل ${users.length}'), selected: _filter == null, onSelected: (_) => setState(() => _filter = null)),
            for (final s in UserStatus.values)
              ChoiceChip(
                label: Text('${statusLabel(s)} ${count(s)}'),
                selected: _filter == s,
                onSelected: (_) => setState(() => _filter = _filter == s ? null : s),
              ),
          ]),
          const SizedBox(height: 8),
          if (shown.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 60),
              child: EmptyView(icon: Icons.people_outline, text: 'ما فيه مستخدمين هنا'),
            ),
          for (final u in shown)
            Card(
              child: ListTile(
                leading: CircleAvatar(child: Text(u.name.isEmpty ? '?' : u.name.characters.first)),
                title: Text(u.name.isEmpty ? '(بدون اسم)' : u.name),
                subtitle: Text(u.email.isEmpty ? u.id : u.email, textDirection: TextDirection.ltr, textAlign: TextAlign.right),
                trailing: StatusChip(user: u),
                onTap: () => _open(u),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _open(AppUser u) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => UserSheet(backend: widget.backend, appId: widget.app.id, user: u),
    );
    _load();
  }
}

String statusLabel(UserStatus s) => switch (s) {
      UserStatus.active => 'نشط',
      UserStatus.suspended => 'محجوب مؤقتاً',
      UserStatus.banned => 'محظور',
    };

class StatusChip extends StatelessWidget {
  final AppUser user;
  const StatusChip({super.key, required this.user});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final s = user.status;
    final (bg, fg) = switch (s) {
      UserStatus.active => (Colors.green.withValues(alpha: .15), Colors.green.shade700),
      UserStatus.suspended => (Colors.orange.withValues(alpha: .18), Colors.orange.shade800),
      UserStatus.banned => (cs.errorContainer, cs.onErrorContainer),
    };
    final text = s == UserStatus.suspended ? 'محجوب ${fmtLeft(user.suspendedUntil!)}' : statusLabel(s);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Text(text, style: TextStyle(color: fg, fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }
}

class UserSheet extends StatefulWidget {
  final AdminBackend backend;
  final String appId;
  final AppUser user;
  const UserSheet({super.key, required this.backend, required this.appId, required this.user});

  @override
  State<UserSheet> createState() => _UserSheetState();
}

class _UserSheetState extends State<UserSheet> {
  late AppUser _u = widget.user;
  bool _busy = false;

  Future<void> _do(Future<void> Function() f, AppUser Function(AppUser) after, String done, {bool close = false}) async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await f();
      if (!mounted) return;
      setState(() => _u = after(_u));
      messenger.showSnackBar(SnackBar(content: Text(done)));
      if (close) Navigator.pop(context);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String?> _reason(String title) async {
    final c = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: TextField(controller: c, decoration: const InputDecoration(labelText: 'السبب (اختياري)')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('تأكيد')),
        ],
      ),
    );
    final text = c.text.trim();
    c.dispose();
    return ok == true ? text : null;
  }

  Future<void> _ban() async {
    final reason = await _reason('حظر ${_u.name}');
    if (reason == null) return;
    await _do(() => widget.backend.setBanned(widget.appId, _u.id, true, reason: reason),
        (u) => u.copyWith(banned: true, banReason: reason), 'تم الحظر');
  }

  Future<void> _unban() => _do(() => widget.backend.setBanned(widget.appId, _u.id, false),
      (u) => u.copyWith(banned: false, banReason: ''), 'تم فك الحظر');

  Future<void> _suspend() async {
    final d = await showDialog<Duration>(context: context, builder: (_) => const _DurationDialog());
    if (d == null || !mounted) return;
    final reason = await _reason('حجب لمدة ${_durationLabel(d)}');
    if (reason == null) return;
    final until = DateTime.now().add(d);
    await _do(() => widget.backend.setSuspendedUntil(widget.appId, _u.id, until, reason: reason),
        (u) => u.copyWith(suspendedUntil: until, banReason: reason), 'تم الحجب حتى ${fmtDate(until)}');
  }

  Future<void> _unsuspend() => _do(() => widget.backend.setSuspendedUntil(widget.appId, _u.id, null),
      (u) => u.copyWith(clearSuspension: true, banReason: ''), 'تم رفع الحجب');

  Future<void> _delete() async {
    final ok = await confirm(context, 'حذف ${_u.name}؟', 'ينحذف حساب المستخدم وبياناته في هذا التطبيق نهائياً، وما يقدر يرجع.',
        action: 'حذف نهائي');
    if (ok) await _do(() => widget.backend.deleteUser(widget.appId, _u.id), (u) => u, 'تم حذف المستخدم', close: true);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final s = _u.status;
    Widget row(String k, String v, {bool ltr = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(width: 110, child: Text(k, style: TextStyle(color: cs.onSurfaceVariant))),
            Expanded(child: SelectableText(v, textDirection: ltr ? TextDirection.ltr : null)),
          ]),
        );

    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            CircleAvatar(radius: 26, child: Text(_u.name.isEmpty ? '?' : _u.name.characters.first, style: const TextStyle(fontSize: 22))),
            const SizedBox(width: 12),
            Expanded(child: Text(_u.name.isEmpty ? '(بدون اسم)' : _u.name, style: Theme.of(context).textTheme.titleLarge)),
            StatusChip(user: _u),
          ]),
          const SizedBox(height: 16),
          row('الإيميل', _u.email.isEmpty ? '—' : _u.email, ltr: true),
          row('المعرّف', _u.id, ltr: true),
          row('تاريخ التسجيل', fmtDate(_u.createdAt)),
          row('آخر ظهور', fmtDate(_u.lastSeen)),
          if (s == UserStatus.suspended) row('محجوب حتى', fmtDate(_u.suspendedUntil)),
          if (s != UserStatus.active && _u.banReason.isNotEmpty) row('السبب', _u.banReason),
          for (final e in _u.extra.entries) row(e.key, e.value),
          const SizedBox(height: 20),
          if (_busy) const LinearProgressIndicator(),
          const SizedBox(height: 8),
          if (s == UserStatus.banned)
            FilledButton.tonalIcon(onPressed: _busy ? null : _unban, icon: const Icon(Icons.lock_open), label: const Text('فك الحظر'))
          else
            FilledButton.tonalIcon(onPressed: _busy ? null : _ban, icon: const Icon(Icons.block), label: const Text('حظر')),
          const SizedBox(height: 8),
          if (s == UserStatus.suspended)
            FilledButton.tonalIcon(onPressed: _busy ? null : _unsuspend, icon: const Icon(Icons.timer_off_outlined), label: const Text('رفع الحجب'))
          else if (s == UserStatus.active)
            FilledButton.tonalIcon(onPressed: _busy ? null : _suspend, icon: const Icon(Icons.timer_outlined), label: const Text('حجب لفترة مؤقتة')),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _busy ? null : _delete,
            style: OutlinedButton.styleFrom(foregroundColor: cs.error, side: BorderSide(color: cs.error)),
            icon: const Icon(Icons.delete_outline),
            label: const Text('حذف الحساب'),
          ),
        ]),
      ),
    );
  }
}

String _durationLabel(Duration d) {
  if (d.inDays >= 1) return '${d.inDays} يوم';
  return '${d.inHours} ساعة';
}

class _DurationDialog extends StatefulWidget {
  const _DurationDialog();

  @override
  State<_DurationDialog> createState() => _DurationDialogState();
}

class _DurationDialogState extends State<_DurationDialog> {
  final _days = TextEditingController();
  static const presets = [
    Duration(hours: 1),
    Duration(hours: 24),
    Duration(days: 3),
    Duration(days: 7),
    Duration(days: 30),
  ];

  @override
  void dispose() {
    _days.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('مدة الحجب'),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final d in presets) ActionChip(label: Text(_durationLabel(d)), onPressed: () => Navigator.pop(context, d)),
        ]),
        const SizedBox(height: 16),
        TextField(
          controller: _days,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'أو اكتب عدد الأيام'),
        ),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
        FilledButton(
          onPressed: () {
            final n = int.tryParse(_days.text.trim());
            if (n != null && n > 0) Navigator.pop(context, Duration(days: n));
          },
          child: const Text('حجب'),
        ),
      ],
    );
  }
}
