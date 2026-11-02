import 'package:flutter/material.dart';

import '../backend/backend.dart';
import '../backend/models.dart';
import '../config.dart';
import 'login_screen.dart';
import 'users_screen.dart';

class AppsScreen extends StatefulWidget {
  final AdminBackend backend;
  final HubConfig config;
  const AppsScreen({super.key, required this.backend, required this.config});

  @override
  State<AppsScreen> createState() => _AppsScreenState();
}

class _AppsScreenState extends State<AppsScreen> {
  late Future<List<AppInfo>> _apps = widget.backend.listApps();

  void _reload() => setState(() => _apps = widget.backend.listApps());

  Future<void> _signOut() async {
    await widget.backend.signOut();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => LoginScreen(config: widget.config)));
  }

  Future<void> _edit([AppInfo? app]) async {
    final result = await showDialog<AppInfo>(context: context, builder: (_) => _AppDialog(app: app));
    if (result == null) return;
    await _run(() => widget.backend.saveApp(result), 'تم حفظ التطبيق');
  }

  Future<void> _delete(AppInfo app) async {
    final ok = await confirm(context, 'إزالة ${app.name}؟',
        'تنحذف بطاقة التطبيق من اللوحة. سجلات المستخدمين في Firebase تبقى ولا تنحذف.');
    if (ok) await _run(() => widget.backend.deleteApp(app.id), 'تمت إزالة التطبيق');
  }

  Future<void> _run(Future<void> Function() f, String done) async {
    try {
      await f();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(done)));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('تطبيقاتي'),
        actions: [
          IconButton(onPressed: _reload, icon: const Icon(Icons.refresh), tooltip: 'تحديث'),
          PopupMenuButton<String>(
            onSelected: (v) => v == 'out' ? _signOut() : null,
            itemBuilder: (_) => [
              PopupMenuItem(enabled: false, child: Text('${widget.backend.adminEmail}\n${widget.backend.label}')),
              const PopupMenuItem(value: 'out', child: Text('تسجيل الخروج')),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(),
        icon: const Icon(Icons.add),
        label: const Text('إضافة تطبيق'),
      ),
      body: FutureBuilder<List<AppInfo>>(
        future: _apps,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
          if (snap.hasError) return ErrorView(message: '${snap.error}', onRetry: _reload);
          final apps = snap.data!..sort((a, b) => a.name.compareTo(b.name));
          if (apps.isEmpty) {
            return const EmptyView(
                icon: Icons.apps, text: 'ما فيه تطبيقات بعد.\nاضغط «إضافة تطبيق» واكتب نفس المعرّف المستخدم داخل تطبيقك.');
          }
          return RefreshIndicator(
            onRefresh: () async => _reload(),
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
              itemCount: apps.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, i) {
                final app = apps[i];
                return Card(
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    leading: CircleAvatar(radius: 24, child: Text(app.icon, style: const TextStyle(fontSize: 24))),
                    title: Text(app.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text(app.description.isEmpty ? app.id : '${app.description} · ${app.id}'),
                    onTap: () => Navigator.of(context)
                        .push(MaterialPageRoute(builder: (_) => UsersScreen(backend: widget.backend, app: app))),
                    trailing: PopupMenuButton<String>(
                      onSelected: (v) => v == 'edit' ? _edit(app) : _delete(app),
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'edit', child: Text('تعديل')),
                        PopupMenuItem(value: 'delete', child: Text('إزالة من اللوحة')),
                      ],
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
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
      title: Text(widget.app == null ? 'إضافة تطبيق' : 'تعديل التطبيق'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
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
              Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
        FilledButton(onPressed: _save, child: const Text('حفظ')),
      ],
    );
  }
}

Future<bool> confirm(BuildContext context, String title, String body, {String action = 'تأكيد', bool danger = true}) async {
  final cs = Theme.of(context).colorScheme;
  return await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
            FilledButton(
              style: danger ? FilledButton.styleFrom(backgroundColor: cs.error, foregroundColor: cs.onError) : null,
              onPressed: () => Navigator.pop(context, true),
              child: Text(action),
            ),
          ],
        ),
      ) ??
      false;
}

class ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const ErrorView({super.key, required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.error_outline, size: 48, color: Theme.of(context).colorScheme.error),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: onRetry, child: const Text('إعادة المحاولة')),
          ]),
        ),
      );
}

class EmptyView extends StatelessWidget {
  final IconData icon;
  final String text;
  const EmptyView({super.key, required this.icon, required this.text});

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 56, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 12),
            Text(text, textAlign: TextAlign.center),
          ]),
        ),
      );
}
