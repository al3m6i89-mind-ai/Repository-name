import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../backend/actions.dart';
import '../backend/backend.dart';
import '../backend/models.dart';
import '../main.dart';
import '../ui/action_dialogs.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';

/// Everything about one account: details, content, activity, and control.
class UserDetailScreen extends StatefulWidget {
  final AppInfo app;
  final AppUser user;
  const UserDetailScreen({super.key, required this.app, required this.user});

  @override
  State<UserDetailScreen> createState() => _UserDetailScreenState();
}

class _UserDetailScreenState extends State<UserDetailScreen> {
  late AppUser _u = widget.user;
  UserInsights? _info;
  Object? _infoError;
  List<LogEntry> _logs = const [];
  String _note = '';
  bool _busy = false;

  AdminBackend get _backend => Hub.of(context).session.backendOf(widget.app);
  UserActions get _acts => UserActions(_backend);
  String get _appId => widget.app.id;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_info == null && _infoError == null) _loadAll();
  }

  Future<void> _loadAll() async {
    final b = _backend;
    final session = Hub.of(context).session;
    // Everything loads at the same time; each part shows as soon as it lands.
    await Future.wait([
      () async {
        try {
          final fresh = await b.getUser(_appId, _u.id);
          if (fresh != null && mounted) {
            setState(() => _u = fresh);
            session.putUser(widget.app, fresh);
          }
        } catch (_) {}
      }(),
      () async {
        try {
          final info = await b.getInsights(_appId, _u);
          if (mounted) setState(() => _info = info);
        } catch (e) {
          if (mounted) setState(() => _infoError = e);
        }
      }(),
      () async {
        try {
          final note = await b.getNote(_appId, _u.id);
          if (mounted) setState(() => _note = note);
        } catch (_) {}
      }(),
      () async {
        try {
          final logs = (await b.listLogs(limit: 300)).where((l) => l.userId == _u.id && l.appId == _appId).toList();
          if (mounted) setState(() => _logs = logs);
        } catch (_) {}
      }(),
    ]);
  }

  /// Like [_run] but shows whether the phone notification was delivered.
  Future<void> _runMsg(Future<String> Function() f) async {
    var result = '';
    await _run(() async => result = await f(), '');
    if (mounted && result.isNotEmpty) toast(context, result, error: !result.contains('✓'));
  }

  Future<void> _run(Future<void> Function() f, String done, {bool pop = false}) async {
    setState(() => _busy = true);
    try {
      await f();
      if (!mounted) return;
      final session = Hub.of(context).session;
      if (done.isNotEmpty) toast(context, done);
      if (pop) {
        session.dropUser(widget.app, _u.id);
        return Navigator.of(context).pop();
      }
      final results = await Future.wait([_backend.getUser(_appId, _u.id), _backend.listLogs(limit: 300)]);
      final fresh = results[0] as AppUser?;
      final logs = (results[1] as List<LogEntry>).where((l) => l.userId == _u.id && l.appId == _appId).toList();
      if (fresh != null) session.putUser(widget.app, fresh);
      if (mounted) {
        setState(() {
          if (fresh != null) _u = fresh;
          _logs = logs;
        });
      }
    } catch (e) {
      if (mounted) toast(context, '$e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        body: NestedScrollView(
          headerSliverBuilder: (context, _) => [
            SliverAppBar(
              pinned: true,
              expandedHeight: 200 + 60 * MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 2.0),
              foregroundColor: Colors.white,
              backgroundColor: const Color(0xFF4C2FC8),
              actions: [
                IconButton(onPressed: _loadAll, icon: const Icon(Icons.refresh_rounded), tooltip: 'تحديث'),
              ],
              flexibleSpace: FlexibleSpaceBar(background: _header()),
              bottom: const TabBar(
                dividerColor: Colors.transparent,
                labelPadding: EdgeInsets.symmetric(horizontal: 4),
                labelColor: Colors.white,
                unselectedLabelColor: Colors.white70,
                indicatorColor: Colors.white,
                labelStyle: TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.w800),
                tabs: [Tab(text: 'التحكم'), Tab(text: 'الحساب'), Tab(text: 'المحتوى'), Tab(text: 'النشاط')],
              ),
            ),
          ],
          body: Column(children: [
            if (_busy) const LinearProgressIndicator(),
            Expanded(child: TabBarView(children: [_controlTab(), _accountTab(), _contentTab(), _activityTab()])),
          ]),
        ),
      ),
    );
  }

  Widget _header() {
    final u = _u;
    final (c, t) = statusLook(u);
    return Container(
      decoration: const BoxDecoration(gradient: Brand.gradient),
      padding: EdgeInsets.fromLTRB(20, MediaQuery.of(context).padding.top + 56, 20, 60),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(26), border: Border.all(color: Colors.white54, width: 2)),
          child: UserAvatar(user: u, size: 76, heroTag: 'av-${widget.app.key}-${u.id}'),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Flexible(
                child: Text(u.displayName,
                    style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800), overflow: TextOverflow.ellipsis),
              ),
              if (u.verified) const Padding(padding: EdgeInsetsDirectional.only(start: 6), child: Icon(Icons.verified_rounded, color: Colors.white, size: 20)),
            ]),
            if (u.email.isNotEmpty)
              Text(u.email, style: const TextStyle(color: Colors.white70), textDirection: TextDirection.ltr, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 10),
            Wrap(spacing: 6, runSpacing: 6, children: [
              _whitePill(t, c),
              _whitePill(userRoles[u.role] ?? u.role, null),
              _whitePill(userPlans[u.plan] ?? u.plan, null),
              _whitePill('${u.points} نقطة', null),
              if (u.warnings > 0) _whitePill('${u.warnings} تحذير', Brand.warning),
            ]),
          ]),
        ),
      ]),
    );
  }

  Widget _whitePill(String t, Color? dot) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(color: Colors.white.withValues(alpha: .18), borderRadius: BorderRadius.circular(20)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (dot != null) ...[Container(width: 8, height: 8, decoration: BoxDecoration(color: dot, shape: BoxShape.circle)), const SizedBox(width: 5)],
          Text(t, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
        ]),
      );

  // Control ---------------------------------------------------------------------

  Widget _controlTab() {
    final u = _u;
    final s = u.status;
    final a = _acts;
    final id = _appId;
    final tiles = <_Act>[
      _Act(Icons.edit_outlined, 'تعديل البيانات', 'الاسم والإيميل والجوال', Brand.primary, _edit),
      _Act(Icons.mail_outline_rounded, 'إرسال رسالة', 'إشعار على جواله', Brand.info, () async {
        final m = await askText(context, 'رسالة إلى ${u.displayName}', label: 'نص الرسالة', required: true, maxLines: 4);
        if (m != null) _runMsg(() => a.message(id, u, m));
      }),
      _Act(Icons.warning_amber_rounded, 'تحذير', u.warnings > 0 ? 'عنده ${u.warnings} تحذير' : 'إنذار مع سبب', Brand.warning, () async {
        final m = await askText(context, 'تحذير ${u.displayName}', label: 'سبب التحذير', required: true, maxLines: 3);
        if (m != null) _runMsg(() => a.warn(id, u, m));
      }),
      if (u.warnings > 0)
        _Act(Icons.cleaning_services_outlined, 'مسح التحذيرات', 'تصفير العداد', Brand.success, () => _run(() => a.clearWarnings(id, u), 'تم مسح التحذيرات')),
      _Act(Icons.tune_rounded, 'تقييد الميزات', u.restrictions.isEmpty ? 'بدون قيود' : u.restrictions.map((k) => userFeatures[k] ?? k).join('، '), Brand.violet, () async {
        final r = await pickRestrictions(context, u.restrictions);
        if (r != null) _run(() => a.setRestrictions(id, u, r), r.isEmpty ? 'تم رفع القيود' : 'تم التقييد');
      }),
      _Act(Icons.badge_outlined, 'تغيير الدور', userRoles[u.role] ?? u.role, Brand.primary, () async {
        final r = await pickOne(context, 'الدور', userRoles, u.role);
        if (r != null && r != u.role) _run(() => a.setRole(id, u, r), 'تم تغيير الدور');
      }),
      _Act(Icons.workspace_premium_outlined, 'تغيير الخطة', userPlans[u.plan] ?? u.plan, Brand.warning, () async {
        final p = await pickOne(context, 'الخطة', userPlans, u.plan);
        if (p != null && p != u.plan) _run(() => a.setPlan(id, u, p), 'تم تغيير الخطة');
      }),
      _Act(Icons.stars_rounded, 'النقاط', 'الرصيد ${u.points}', Brand.success, _points),
      _Act(u.verified ? Icons.verified_rounded : Icons.verified_outlined, u.verified ? 'إلغاء التوثيق' : 'توثيق الحساب',
          u.verified ? 'موثّق حالياً' : 'علامة التوثيق', Brand.info, () => _run(() => a.setVerified(id, u, !u.verified), 'تم')),
      _Act(Icons.logout_rounded, 'تسجيل خروج إجباري', 'من كل الأجهزة', Brand.violet, () async {
        if (await confirm(context, 'تسجيل خروج ${u.displayName}؟', 'يخرج من كل أجهزته ويلزمه يسجّل دخول من جديد.', danger: false)) {
          _run(() => a.forceLogout(id, u), 'تم تسجيل خروجه');
        }
      }),
      if (s == UserStatus.suspended)
        _Act(Icons.timer_off_outlined, 'رفع الحجب', 'محجوب حتى ${fmtDateTime(u.suspendedUntil)}', Brand.success, () => _run(() => a.unsuspend(id, u), 'تم رفع الحجب'))
      else if (!u.banned)
        _Act(Icons.timer_outlined, 'حجب مؤقت', 'يمنع دخوله لمدة', Brand.warning, () async {
          final d = await pickDuration(context);
          if (d == null || !mounted) return;
          final r = await askText(context, 'حجب ${durationLabel(d)}', label: 'السبب (اختياري)');
          if (r != null) _run(() => a.suspend(id, u, DateTime.now().add(d), r), 'تم الحجب ${durationLabel(d)}');
        }),
      if (u.banned)
        _Act(Icons.lock_open_rounded, 'فك الحظر', u.banReason.isEmpty ? 'محظور' : u.banReason, Brand.success, () => _run(() => a.unban(id, u), 'تم فك الحظر'))
      else
        _Act(Icons.block_rounded, 'حظر دائم', 'يمنع دخوله نهائياً', Brand.danger, () async {
          final r = await askText(context, 'حظر ${u.displayName}', label: 'السبب (اختياري)');
          if (r != null) _run(() => a.ban(id, u, r), 'تم الحظر');
        }),
      _Act(Icons.delete_forever_rounded, 'حذف الحساب', 'نهائي ولا يرجع', Brand.danger, () async {
        if (await confirm(context, 'حذف ${u.displayName}؟', 'ينحذف الحساب نهائياً من التطبيق، وما يقدر يرجع.', action: 'حذف نهائي')) {
          _run(() => a.delete(id, u), 'تم حذف الحساب', pop: true);
        }
      }),
    ];
    final wide = MediaQuery.of(context).size.width >= 700;
    return ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 32), children: [
      if (u.adminMessage.isNotEmpty)
        Card(
          color: Brand.info.withValues(alpha: .08),
          child: ListTile(
            leading: const Icon(Icons.chat_bubble_outline_rounded, color: Brand.info),
            title: const Text('آخر رسالة أرسلتها له', style: TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text('${u.adminMessage}\n${fmtAgo(u.adminMessageAt)}'),
            isThreeLine: true,
          ),
        ),
      if (u.adminMessage.isNotEmpty) const SizedBox(height: 12),
      GridView(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: wide ? 4 : 2,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          mainAxisExtent: 128 * MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.6),
        ),
        children: [for (final t in tiles) _actTile(t)],
      ),
      const SectionTitle('ملاحظاتك الخاصة'),
      Card(
        child: ListTile(
          leading: const Icon(Icons.sticky_note_2_outlined),
          title: Text(_note.isEmpty ? 'أضف ملاحظة لا يشوفها المستخدم' : _note, style: const TextStyle(height: 1.5)),
          trailing: const Icon(Icons.edit_outlined, size: 18),
          onTap: () async {
            final n = await askText(context, 'ملاحظة خاصة', initial: _note, maxLines: 5);
            if (n == null) return;
            await _backend.setNote(_appId, u.id, n);
            if (mounted) setState(() => _note = n);
          },
        ),
      ),
    ]);
  }

  Widget _actTile(_Act t) => Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: _busy ? null : t.onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: t.color.withValues(alpha: .13), borderRadius: BorderRadius.circular(12)),
                child: Icon(t.icon, color: t.color, size: 22),
              ),
              const Spacer(),
              Text(t.title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
              const SizedBox(height: 2),
              Text(t.subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12)),
            ]),
          ),
        ),
      );

  Future<void> _edit() async {
    final name = TextEditingController(text: _u.name);
    final email = TextEditingController(text: _u.email);
    final phone = TextEditingController(text: _u.phone);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تعديل البيانات', style: TextStyle(fontWeight: FontWeight.w800)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: name, decoration: const InputDecoration(labelText: 'الاسم')),
          const SizedBox(height: 10),
          TextField(controller: email, textDirection: TextDirection.ltr, decoration: const InputDecoration(labelText: 'الإيميل')),
          const SizedBox(height: 10),
          TextField(controller: phone, textDirection: TextDirection.ltr, decoration: const InputDecoration(labelText: 'الجوال', hintText: '+9665…')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('حفظ')),
        ],
      ),
    );
    if (ok == true) {
      await _run(() => _acts.editProfile(_appId, _u, name: name.text.trim(), email: email.text.trim(), phone: phone.text.trim()),
          'تم حفظ البيانات');
    }
    for (final c in [name, email, phone]) {
      c.dispose();
    }
  }

  Future<void> _points() async {
    final v = await askText(context, 'تعديل النقاط (الرصيد ${_u.points})',
        label: 'اكتب رقم موجب للإضافة أو سالب للخصم', keyboard: const TextInputType.numberWithOptions(signed: true));
    final n = int.tryParse((v ?? '').replaceAll('+', '').trim());
    if (n == null || n == 0) return;
    await _run(() => _acts.addPoints(_appId, _u, n), n > 0 ? 'تمت إضافة $n نقطة' : 'تم خصم ${-n} نقطة');
  }

  // Account ---------------------------------------------------------------------

  Widget _accountTab() {
    final u = _u;
    final info = _info;
    final rows = <(String, String)>[
      ('الاسم', u.displayName),
      if (u.email.isNotEmpty) ('الإيميل', u.email),
      if (u.phone.isNotEmpty) ('الجوال', u.phone),
      ('تاريخ التسجيل', fmtDateTime(u.createdAt)),
      ('آخر ظهور', '${fmtDateTime(u.lastSeen)}  (${fmtAgo(u.lastSeen)})'),
      if (u.lastLogin != null) ('آخر تسجيل دخول', fmtDateTime(u.lastLogin)),
      if (u.providers.isNotEmpty) ('طرق الدخول', u.providers.map((p) => providerNames[p] ?? p).join('، ')),
      ('الحالة', statusLook(u).$2),
      if (u.banReason.isNotEmpty) ('السبب', u.banReason),
      if (u.suspendedUntil != null && u.status == UserStatus.suspended) ('محجوب حتى', fmtDateTime(u.suspendedUntil)),
      ('الدور', userRoles[u.role] ?? u.role),
      ('الخطة', userPlans[u.plan] ?? u.plan),
      ('النقاط', '${u.points}'),
      if (u.restrictions.isNotEmpty) ('ميزات مقفلة', u.restrictions.map((k) => userFeatures[k] ?? k).join('، ')),
      if (u.warnings > 0) ('التحذيرات', '${u.warnings} · آخرها: ${u.lastWarning}'),
      if (u.forceLogoutAt != null) ('آخر طرد من الجلسات', fmtDateTime(u.forceLogoutAt)),
      for (final e in u.extra.entries) (e.key, e.value),
    ];
    final more = info?.account.entries.where((e) => e.value.isNotEmpty && !rows.any((r) => r.$1 == e.key)).toList() ?? [];
    return ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
      const SectionTitle('معلومات الحساب'),
      _kvCard(rows),
      if (more.isNotEmpty) ...[
        const SectionTitle('تفاصيل تقنية'),
        _kvCard([for (final e in more) (e.key, e.value)]),
      ],
      if (info == null && _infoError == null) const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
      if (_infoError != null) Padding(padding: const EdgeInsets.all(12), child: Text('$_infoError', style: const TextStyle(color: Brand.danger))),
    ]);
  }

  Widget _kvCard(List<(String, String)> rows) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      child: Column(children: [
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) const Divider(height: 1, indent: 14, endIndent: 14),
          InkWell(
            onLongPress: () {
              Clipboard.setData(ClipboardData(text: rows[i].$2));
              toast(context, 'تم النسخ');
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SizedBox(width: 130, child: Text(rows[i].$1, style: TextStyle(color: cs.onSurfaceVariant))),
                Expanded(child: Text(rows[i].$2, style: const TextStyle(fontWeight: FontWeight.w600, height: 1.4))),
              ]),
            ),
          ),
        ],
      ]),
    );
  }

  // Content -----------------------------------------------------------------------

  Widget _contentTab() {
    final info = _info;
    if (info == null) {
      return _infoError != null
          ? ErrorView(message: '$_infoError', onRetry: _loadAll)
          : const Center(child: CircularProgressIndicator());
    }
    final social = info.data.where((d) => contentKind(d.path).$3).toList()
      ..sort((a, b) => (b.when ?? DateTime(0)).compareTo(a.when ?? DateTime(0)));
    final other = info.data.where((d) => !contentKind(d.path).$3).toList();
    final groups = <String, int>{};
    for (final d in social) {
      final k = contentKind(d.path).$1;
      groups[k] = (groups[k] ?? 0) + 1;
    }
    final stories = social.where((d) => contentKind(d.path).$1 == 'قصة').toList();
    final posts = social.where((d) => contentKind(d.path).$1 != 'قصة').toList();
    return ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 32), children: [
      for (final n in info.notes)
        Card(
          color: Brand.warning.withValues(alpha: .1),
          child: ListTile(leading: const Icon(Icons.info_outline, color: Brand.warning), title: Text(n)),
        ),
      if (groups.isNotEmpty)
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final g in groups.entries) Pill('${g.key} ${g.value}', color: Brand.primary),
        ]),
      if (stories.isNotEmpty) ...[
        const SectionTitle('القصص'),
        SizedBox(
          height: 190,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: stories.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (_, i) => _story(stories[i]),
          ),
        ),
      ],
      if (posts.isNotEmpty) ...[
        const SectionTitle('المنشورات واللحظات والتفاعل'),
        for (final d in posts) ...[_post(d), const SizedBox(height: 10)],
      ],
      if (other.isNotEmpty) ...[
        const SectionTitle('بيانات أخرى محفوظة'),
        for (final d in other) ...[_record(d), const SizedBox(height: 8)],
      ],
      if (info.data.isEmpty)
        const Padding(
          padding: EdgeInsets.only(top: 40),
          child: EmptyView(icon: Icons.inventory_2_outlined, title: 'ما لقيت بيانات لهذا المستخدم', text: 'تظهر هنا منشوراته وقصصه وأي سجلات تخصه في قاعدة البيانات.'),
        ),
    ]);
  }

  Future<void> _deleteDoc(DataDoc d) async {
    final kind = contentKind(d.path).$1;
    if (!await confirm(context, 'حذف هذا الـ$kind؟', 'ينحذف من قاعدة بيانات التطبيق نهائياً.\n${d.path}', action: 'حذف')) return;
    await _run(() async {
      await _backend.deleteData(d.path);
      await _backend.addLog(LogEntry(
        appId: _appId,
        userId: _u.id,
        userName: _u.displayName,
        action: 'حذف $kind',
        detail: d.mainText.isEmpty ? d.path : d.mainText,
        by: _backend.adminEmail ?? '',
        at: DateTime.now(),
      ));
      final info = await _backend.getInsights(_appId, _u);
      if (mounted) setState(() => _info = info);
    }, 'تم الحذف');
  }

  Widget _media(String url, {double? height, BoxFit fit = BoxFit.cover}) => Image.network(
        url,
        height: height,
        width: double.infinity,
        fit: fit,
        errorBuilder: (_, __, ___) => Container(
          height: height ?? 120,
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          alignment: Alignment.center,
          child: const Icon(Icons.broken_image_outlined),
        ),
        loadingBuilder: (_, child, p) => p == null
            ? child
            : Container(height: height ?? 120, alignment: Alignment.center, child: const CircularProgressIndicator(strokeWidth: 2)),
      );

  Widget _story(DataDoc d) {
    final m = d.media;
    return SizedBox(
      width: 112,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: Stack(fit: StackFit.expand, children: [
          if (m.isNotEmpty) _media(m.first) else Container(decoration: const BoxDecoration(gradient: Brand.gradient)),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, Colors.black54]),
            ),
          ),
          PositionedDirectional(
            bottom: 8,
            start: 8,
            end: 8,
            child: Text(
              [fmtAgo(d.when), if (d.count(['views']) != null) '👁 ${d.count(['views'])}'].join(' · '),
              style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700),
            ),
          ),
          PositionedDirectional(
            top: 2,
            end: 2,
            child: IconButton.filledTonal(
              iconSize: 16,
              visualDensity: VisualDensity.compact,
              onPressed: () => _deleteDoc(d),
              icon: const Icon(Icons.delete_outline_rounded),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _post(DataDoc d) {
    final (kind, icon, _) = contentKind(d.path);
    final m = d.media;
    final likes = d.count(['likes', 'likesCount', 'likeCount']);
    final comments = d.count(['comments', 'commentsCount', 'commentCount']);
    final cs = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        ListTile(
          leading: UserAvatar(user: _u, size: 38),
          title: Text(_u.displayName, style: const TextStyle(fontWeight: FontWeight.w800)),
          subtitle: Text('$icon $kind · ${fmtAgo(d.when)}'),
          trailing: PopupMenuButton<String>(
            onSelected: (v) => v == 'delete' ? _deleteDoc(d) : _showRaw(d),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'raw', child: Text('كل الحقول')),
              PopupMenuItem(value: 'delete', child: Text('حذف', style: TextStyle(color: Brand.danger))),
            ],
          ),
        ),
        if (d.mainText.isNotEmpty)
          Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 12), child: Text(d.mainText, style: const TextStyle(fontSize: 15, height: 1.5))),
        if (m.isNotEmpty) _media(m.first, height: 260),
        if (likes != null || comments != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
            child: Row(children: [
              if (likes != null) ...[const Icon(Icons.favorite_rounded, size: 18, color: Brand.danger), const SizedBox(width: 4), Text('$likes')],
              const SizedBox(width: 16),
              if (comments != null) ...[Icon(Icons.mode_comment_outlined, size: 18, color: cs.onSurfaceVariant), const SizedBox(width: 4), Text('$comments')],
            ]),
          ),
      ]),
    );
  }

  Widget _record(DataDoc d) {
    final (kind, icon, _) = contentKind(d.path);
    return Card(
      child: ListTile(
        leading: Text(icon, style: const TextStyle(fontSize: 24)),
        title: Text(d.mainText.isNotEmpty ? d.mainText : kind, style: const TextStyle(fontWeight: FontWeight.w700), maxLines: 2, overflow: TextOverflow.ellipsis),
        subtitle: Text(d.path, textDirection: TextDirection.ltr, textAlign: TextAlign.right, style: const TextStyle(fontSize: 12)),
        trailing: const Icon(Icons.chevron_left_rounded),
        onTap: () => _showRaw(d),
      ),
    );
  }

  void _showRaw(DataDoc d) {
    String show(Object? v) => v is DateTime ? fmtDateTime(v) : '$v';
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: .6,
        maxChildSize: .95,
        builder: (_, sc) => ListView(controller: sc, padding: const EdgeInsets.fromLTRB(20, 0, 20, 24), children: [
          Text(contentKind(d.path).$1, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          Text(d.path, textDirection: TextDirection.ltr, style: TextStyle(color: Theme.of(ctx).colorScheme.onSurfaceVariant, fontSize: 12)),
          const SizedBox(height: 12),
          for (final m in d.media) Padding(padding: const EdgeInsets.only(bottom: 10), child: ClipRRect(borderRadius: BorderRadius.circular(14), child: _media(m, height: 220))),
          for (final e in d.fields.entries)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SizedBox(width: 120, child: Text(e.key, textDirection: TextDirection.ltr, style: TextStyle(color: Theme.of(ctx).colorScheme.onSurfaceVariant))),
                Expanded(child: SelectableText(show(e.value))),
              ]),
            ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(foregroundColor: Brand.danger),
            onPressed: () {
              Navigator.pop(ctx);
              _deleteDoc(d);
            },
            icon: const Icon(Icons.delete_outline_rounded),
            label: const Text('حذف هذا السجل'),
          ),
        ]),
      ),
    );
  }

  // Activity ----------------------------------------------------------------------

  Widget _activityTab() {
    final items = <ActivityEvent>[
      ...?_info?.events,
      for (final l in _logs)
        ActivityEvent(at: l.at, title: 'المشرف: ${l.action}', detail: [l.detail, l.by].where((s) => s.isNotEmpty).join(' · '), icon: '🛡️'),
    ]..sort((a, b) => b.at.compareTo(a.at));
    if (_info == null && _infoError == null) return const Center(child: CircularProgressIndicator());
    if (items.isEmpty) return const EmptyView(icon: Icons.timeline_rounded, title: 'ما فيه نشاط مسجل');
    final cs = Theme.of(context).colorScheme;
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      itemCount: items.length,
      itemBuilder: (_, i) {
        final e = items[i];
        return IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SizedBox(
              width: 44,
              child: Column(children: [
                Container(
                  width: 36,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: cs.primaryContainer.withValues(alpha: .6), shape: BoxShape.circle),
                  child: Text(e.icon, style: const TextStyle(fontSize: 16)),
                ),
                if (i < items.length - 1) Expanded(child: Container(width: 2, color: cs.outlineVariant)),
              ]),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 18, top: 4),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(e.title, style: const TextStyle(fontWeight: FontWeight.w800)),
                  if (e.detail.isNotEmpty) Text(e.detail, style: TextStyle(color: cs.onSurfaceVariant, height: 1.4)),
                  const SizedBox(height: 2),
                  Text('${fmtDateTime(e.at)} · ${fmtAgo(e.at)}', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
                ]),
              ),
            ),
          ]),
        );
      },
    );
  }
}

class _Act {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;
  _Act(this.icon, this.title, this.subtitle, this.color, this.onTap);
}
