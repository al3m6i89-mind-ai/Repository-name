import 'package:flutter/material.dart';

import '../backend/models.dart';
import '../backend/session.dart';
import '../main.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'start_screens.dart';
import 'users_screen.dart';

class AppsScreen extends StatefulWidget {
  const AppsScreen({super.key});

  @override
  State<AppsScreen> createState() => _AppsScreenState();
}

class _AppsScreenState extends State<AppsScreen> {
  Future<void> _reload() => Hub.of(context).session.refreshAll();

  Future<void> _addAccount() async {
    final ok = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => const AddConnectionScreen()));
    if (ok == true) _reload();
  }

  Future<void> _editApp(Linked l, [AppInfo? app]) async {
    final result = await showDialog<AppInfo>(context: context, builder: (_) => _AppDialog(app: app));
    if (result == null || !mounted) return;
    try {
      await l.backend.saveApp(result);
      if (mounted) toast(context, 'تم حفظ التطبيق');
    } catch (e) {
      if (mounted) toast(context, '$e', error: true);
    }
    _reload();
  }

  Future<void> _removeApp(Linked l, AppInfo app) async {
    if (!await confirm(context, 'إزالة ${app.name}؟', 'تنحذف بطاقة التطبيق من اللوحة فقط. المستخدمون يبقون.')) return;
    await l.backend.deleteApp(app.id);
    _reload();
  }

  Future<void> _renameAccount(Linked l) async {
    final name = await askText(context, 'اسم الحساب', initial: l.connection.label, required: true);
    if (name == null || !mounted) return;
    final icon = await askText(context, 'أيقونة (إيموجي)', initial: l.connection.icon) ?? l.connection.icon;
    if (!mounted) return;
    await Hub.of(context).session.rename(l, name, icon.isEmpty ? l.connection.icon : icon);
    _reload();
  }

  Future<void> _removeAccount(Linked l) async {
    final ok = await confirm(context, 'فصل ${l.connection.label}؟',
        'يُحذف الحساب من هذا الجهاز فقط مع ملاحظاته وسجله المحلي. ما يتأثر شي في Firebase.',
        action: 'فصل');
    if (!ok || !mounted) return;
    await Hub.of(context).session.remove(l);
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    final session = Hub.of(context).session;
    return Scaffold(
      appBar: AppBar(
        title: const Text('التطبيقات'),
        actions: [IconButton(onPressed: _reload, icon: const Icon(Icons.refresh_rounded), tooltip: 'تحديث')],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'add-account',
        onPressed: _addAccount,
        icon: const Icon(Icons.add_link_rounded),
        label: const Text('ربط حساب'),
      ),
      body: ListenableBuilder(
        listenable: session,
        builder: (context, _) {
          final apps = [for (final d in session.apps) d.app];
          if (session.linked.isEmpty) {
            return EmptyView(
              icon: Icons.link_off_rounded,
              title: 'ما فيه حسابات مربوطة',
              text: 'اربط أول حساب Firebase عشان تظهر تطبيقاتك.',
              action: FilledButton.icon(
                  onPressed: _addAccount, icon: const Icon(Icons.add_link_rounded), label: const Text('ربط حساب')),
            );
          }
          return RefreshIndicator(
            onRefresh: _reload,
            child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 100), children: [
              for (final l in session.linked)
                ..._group(l, apps.where((a) => a.connectionId == l.connection.id).toList()),
            ]),
          );
        },
      ),
    );
  }

  List<Widget> _group(Linked l, List<AppInfo> apps) {
    final cs = Theme.of(context).colorScheme;
    final c = l.connection;
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 18, 0, 8),
        child: Row(children: [
          Text(c.icon, style: const TextStyle(fontSize: 20)),
          const SizedBox(width: 8),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(c.label, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              Text('${c.typeLabel}${c.projectId.isEmpty ? '' : ' · ${c.projectId}'}',
                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
            ]),
          ),
          PopupMenuButton<String>(
            onSelected: (v) => switch (v) {
              'rename' => _renameAccount(l),
              'add' => _editApp(l),
              'retry' => Hub.of(context).session.retry(l).then((_) => _reload()),
              _ => _removeAccount(l),
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'rename', child: Text('تغيير الاسم والأيقونة')),
              if (c.type != ConnectionType.serviceAccount)
                const PopupMenuItem(value: 'add', child: Text('إضافة تطبيق')),
              const PopupMenuItem(value: 'retry', child: Text('إعادة الاتصال')),
              const PopupMenuItem(value: 'remove', child: Text('فصل الحساب', style: TextStyle(color: Brand.danger))),
            ],
          ),
        ]),
      ),
      if (l.connecting && apps.isEmpty)
        const SkeletonList(count: 1)
      else if (!l.ok)
        Card(
          color: Brand.danger.withValues(alpha: .08),
          child: ListTile(
            leading: const Icon(Icons.error_outline_rounded, color: Brand.danger),
            title: const Text('تعذّر الاتصال بهذا الحساب', style: TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text(l.error ?? ''),
            trailing: TextButton(
              onPressed: () => Hub.of(context).session.retry(l).then((_) => _reload()),
              child: const Text('إعادة'),
            ),
          ),
        )
      else if (apps.isEmpty)
        Card(
          child: ListTile(
            leading: const Icon(Icons.add_box_outlined),
            title: const Text('ما فيه تطبيقات في هذا الحساب'),
            subtitle: const Text('اضغط لإضافة تطبيق بنفس المعرّف المستخدم داخل كودك'),
            onTap: () => _editApp(l),
          ),
        )
      else
        for (final app in apps) ...[
          Builder(builder: (context) {
            final n = Hub.of(context).session.dataOf(app)?.users.length;
            return Card(
              clipBehavior: Clip.antiAlias,
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                leading: AppBadge(app: app),
                title: Text(app.name, style: const TextStyle(fontWeight: FontWeight.w800)),
                subtitle:
                    Text([if (n != null) '$n مستخدم', app.description.isEmpty ? app.id : app.description].join(' · ')),
                trailing: c.type == ConnectionType.serviceAccount
                    ? const Icon(Icons.chevron_left_rounded)
                    : PopupMenuButton<String>(
                        onSelected: (v) => v == 'edit' ? _editApp(l, app) : _removeApp(l, app),
                        itemBuilder: (_) => const [
                          PopupMenuItem(value: 'edit', child: Text('تعديل')),
                          PopupMenuItem(value: 'delete', child: Text('إزالة من اللوحة')),
                        ],
                      ),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => UsersScreen(app: app))),
              ),
            );
          }),
          const SizedBox(height: 8),
        ],
    ];
  }
}

class _AppDialog extends StatefulWidget {
  final AppInfo? app;
  const _AppDialog({this.app});

  @override
  State<_AppDialog> createState() => _AppDialogState();
}

class _AppDialogState extends State<_AppDialog> {
  late final _name = TextEditingController(text: widget.app?.name);
  late final _id = TextEditingController(text: widget.app?.id);
  late final _icon = TextEditingController(text: widget.app?.icon ?? '📱');
  late final _desc = TextEditingController(text: widget.app?.description);
  String? _error;

  @override
  void dispose() {
    for (final c in [_name, _id, _icon, _desc]) {
      c.dispose();
    }
    super.dispose();
  }

  void _save() {
    final id = _id.text.trim();
    if (_name.text.trim().isEmpty) return setState(() => _error = 'اكتب اسم التطبيق');
    if (!RegExp(r'^[a-z0-9][a-z0-9_-]*$').hasMatch(id)) {
      return setState(() => _error = 'المعرّف بالإنجليزي الصغير والأرقام و - فقط، مثل my-app');
    }
    Navigator.pop(
      context,
      AppInfo(
        id: id,
        name: _name.text.trim(),
        icon: _icon.text.trim().isEmpty ? '📱' : _icon.text.trim(),
        description: _desc.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.app == null ? 'إضافة تطبيق' : 'تعديل التطبيق',
          style: const TextStyle(fontWeight: FontWeight.w800)),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: _name, decoration: const InputDecoration(labelText: 'الاسم')),
          const SizedBox(height: 10),
          TextField(
            controller: _id,
            enabled: widget.app == null,
            textDirection: TextDirection.ltr,
            decoration: const InputDecoration(labelText: 'المعرّف', hintText: 'my-app'),
          ),
          const SizedBox(height: 10),
          TextField(controller: _icon, decoration: const InputDecoration(labelText: 'أيقونة (إيموجي)')),
          const SizedBox(height: 10),
          TextField(controller: _desc, decoration: const InputDecoration(labelText: 'وصف قصير')),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!, style: const TextStyle(color: Brand.danger)),
          ],
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
        FilledButton(onPressed: _save, child: const Text('حفظ')),
      ],
    );
  }
}
