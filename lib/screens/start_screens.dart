import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../backend/backend.dart';
import '../backend/service_account_backend.dart';
import '../backend/session.dart';
import '../main.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'setup_guide_screen.dart';
import 'shell.dart';

/// Loads saved accounts, then shows the lock, the welcome page or the hub.
class StartScreen extends StatefulWidget {
  const StartScreen({super.key});

  @override
  State<StartScreen> createState() => _StartScreenState();
}

class _StartScreenState extends State<StartScreen> {
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final s = Hub.of(context).session;
    if (!s.loaded) s.load().then((_) => mounted ? _route() : null);
  }

  void _route() {
    final s = Hub.of(context).session;
    final Widget next = s.lockHash.isNotEmpty
        ? const LockScreen()
        : s.linked.isEmpty
            ? const WelcomeScreen()
            : const Shell();
    Navigator.of(context).pushReplacement(PageRouteBuilder(
      pageBuilder: (_, __, ___) => next,
      transitionsBuilder: (_, a, __, child) => FadeTransition(opacity: a, child: child),
    ));
  }

  @override
  Widget build(BuildContext context) => const Scaffold(
        body: DecoratedBox(
          decoration: BoxDecoration(gradient: Brand.gradient),
          child: Center(child: LogoMark(size: 96)),
        ),
      );
}

class LogoMark extends StatelessWidget {
  final double size;
  const LogoMark({super.key, this.size = 72});

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(size * .26),
        child: Image.asset('assets/branding/icon.png', width: size, height: size),
      );
}

/// Asks for the hub's own password when one is set.
class LockScreen extends StatefulWidget {
  const LockScreen({super.key});

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  final _c = TextEditingController();
  String? _error;
  bool _hide = true;

  void _open() {
    final s = Hub.of(context).session;
    if (!s.checkLock(_c.text)) return setState(() => _error = 'كلمة المرور غير صحيحة');
    Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => s.linked.isEmpty ? const WelcomeScreen() : const Shell()));
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: ListView(shrinkWrap: true, padding: const EdgeInsets.all(28), children: [
              const Center(child: LogoMark(size: 88)),
              const SizedBox(height: 22),
              const Text('لوحة تطبيقاتي', textAlign: TextAlign.center, style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              Text('اكتب كلمة مرور اللوحة للدخول', textAlign: TextAlign.center,
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
              const SizedBox(height: 26),
              TextField(
                controller: _c,
                obscureText: _hide,
                autofocus: true,
                onSubmitted: (_) => _open(),
                decoration: InputDecoration(
                  labelText: 'كلمة المرور',
                  prefixIcon: const Icon(Icons.lock_outline_rounded),
                  errorText: _error,
                  suffixIcon: IconButton(
                    icon: Icon(_hide ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                    onPressed: () => setState(() => _hide = !_hide),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              FilledButton.icon(onPressed: _open, icon: const Icon(Icons.login_rounded), label: const Text('دخول')),
            ]),
          ),
        ),
      ),
    );
  }
}

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  bool _busy = false;

  Future<void> _demo() async {
    setState(() => _busy = true);
    final s = Hub.of(context).session;
    await s.add(Connection(id: 'demo', type: ConnectionType.demo, label: 'تجريبي', icon: '🧪'));
    if (!mounted) return;
    Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const Shell()));
  }

  Future<void> _add() async {
    final ok = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => const AddConnectionScreen()));
    if (ok == true && mounted) Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const Shell()));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    Widget feature(IconData i, String t, String d) => Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: cs.primaryContainer.withValues(alpha: .6), borderRadius: BorderRadius.circular(12)),
              child: Icon(i, color: cs.primary, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(t, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                const SizedBox(height: 2),
                Text(d, style: TextStyle(color: cs.onSurfaceVariant, height: 1.4)),
              ]),
            ),
          ]),
        );
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: ListView(padding: EdgeInsets.zero, children: [
            Container(
              padding: EdgeInsets.fromLTRB(28, MediaQuery.of(context).padding.top + 40, 28, 36),
              decoration: const BoxDecoration(
                gradient: Brand.gradient,
                borderRadius: BorderRadius.vertical(bottom: Radius.circular(32)),
              ),
              child: const Column(children: [
                LogoMark(size: 92),
                SizedBox(height: 18),
                Text('لوحة تطبيقاتي', style: TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.w800)),
                SizedBox(height: 8),
                Text('تحكم كامل بمستخدمي كل تطبيقاتك من مكان واحد',
                    textAlign: TextAlign.center, style: TextStyle(color: Colors.white70, fontSize: 15)),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                feature(Icons.hub_outlined, 'كل حساباتك في لوحة واحدة', 'اربط أكثر من مشروع Firebase وشوف كل التطبيقات مع بعض.'),
                feature(Icons.manage_accounts_outlined, 'صلاحيات كاملة', 'حظر، حجب مؤقت، تحذير، رسائل، تقييد ميزات، طرد من الجلسات، وحذف.'),
                feature(Icons.travel_explore_outlined, 'كل تفاصيل الحساب', 'بياناته ومنشوراته وقصصه ونشاطه، مع سجل لكل إجراء.'),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _busy ? null : _add,
                  icon: const Icon(Icons.add_link_rounded),
                  label: const Text('ربط حساب Firebase'),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _demo,
                  icon: const Icon(Icons.science_outlined),
                  label: const Text('جرّب ببيانات تجريبية'),
                ),
                const SizedBox(height: 6),
                TextButton.icon(
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SetupGuideScreen())),
                  icon: const Icon(Icons.menu_book_outlined),
                  label: const Text('شرح الإعداد خطوة بخطوة'),
                ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Adds a Firebase project: with a service-account key (full control) or
/// with admin email + password (apps that use the hub's client helper).
class AddConnectionScreen extends StatefulWidget {
  const AddConnectionScreen({super.key});

  @override
  State<AddConnectionScreen> createState() => _AddConnectionScreenState();
}

class _AddConnectionScreenState extends State<AddConnectionScreen> {
  ConnectionType _type = ConnectionType.serviceAccount;
  final _label = TextEditingController();
  final _icon = TextEditingController(text: '🔥');
  final _json = TextEditingController();
  final _projectId = TextEditingController();
  final _apiKey = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  String? _fileName;
  String? _error;
  bool _busy = false;
  bool _hide = true;

  @override
  void dispose() {
    for (final c in [_label, _icon, _json, _projectId, _apiKey, _email, _password]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pick() async {
    try {
      final f = await FilePicker.pickFile(type: FileType.any);
      if (f == null) return;
      final text = utf8.decode(await f.readAsBytes());
      final key = ServiceAccountBackend.parseKey(text);
      setState(() {
        _json.text = text;
        _fileName = f.name;
        _error = null;
        if (_label.text.isEmpty) _label.text = '${key['project_id']}';
      });
    } on BackendError catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = 'تعذّر فتح الملف: $e');
    }
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final s = Hub.of(context).session;
    try {
      final Connection c;
      if (_type == ConnectionType.serviceAccount) {
        final key = ServiceAccountBackend.parseKey(_json.text);
        c = Connection(
          id: 'sa-${key['project_id']}',
          type: ConnectionType.serviceAccount,
          label: _label.text.trim().isEmpty ? '${key['project_id']}' : _label.text.trim(),
          icon: _icon.text.trim().isEmpty ? '🔥' : _icon.text.trim(),
          data: {'serviceAccount': _json.text.trim(), 'projectId': '${key['project_id']}'},
        );
        await s.add(c);
      } else {
        if (_projectId.text.trim().isEmpty || _apiKey.text.trim().isEmpty) {
          throw BackendError('اكتب معرّف المشروع ومفتاح Web API');
        }
        if (_email.text.trim().isEmpty || _password.text.isEmpty) throw BackendError('اكتب الإيميل وكلمة المرور');
        c = Connection(
          id: 'hub-${_projectId.text.trim()}',
          type: ConnectionType.hub,
          label: _label.text.trim().isEmpty ? _projectId.text.trim() : _label.text.trim(),
          icon: _icon.text.trim().isEmpty ? '🔥' : _icon.text.trim(),
          data: {'projectId': _projectId.text.trim(), 'apiKey': _apiKey.text.trim(), 'email': _email.text.trim()},
        );
        await s.add(c, password: _password.text);
      }
      if (!mounted) return;
      toast(context, 'تم ربط ${c.label} ✓');
      Navigator.of(context).pop(true);
    } on BackendError catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = 'تعذّر الاتصال: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final sa = _type == ConnectionType.serviceAccount;
    return Scaffold(
      appBar: AppBar(title: const Text('ربط حساب Firebase')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 32), children: [
            SegmentedButton<ConnectionType>(
              segments: const [
                ButtonSegment(value: ConnectionType.serviceAccount, label: Text('ملف حساب الخدمة'), icon: Icon(Icons.key_rounded)),
                ButtonSegment(value: ConnectionType.hub, label: Text('إيميل وكلمة مرور'), icon: Icon(Icons.mail_outline)),
              ],
              selected: {_type},
              onSelectionChanged: (v) => setState(() {
                _type = v.first;
                _error = null;
              }),
            ),
            const SizedBox(height: 14),
            Card(
              color: cs.primaryContainer.withValues(alpha: .35),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(sa ? Icons.verified_user_outlined : Icons.info_outline, color: cs.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      sa
                          ? 'موصى به. يعطي تحكم كامل بكل مستخدمي المشروع (حتى تطبيقاتك الحالية) بدون تعديل كودها، ويقرأ بياناتهم ومحتواهم.'
                          : 'للتطبيقات اللي أضفت لها ملف الربط من هذه اللوحة. تدخل بإيميل المشرف وكلمة المرور.',
                      style: const TextStyle(height: 1.5),
                    ),
                  ),
                ]),
              ),
            ),
            const SizedBox(height: 16),
            Row(children: [
              SizedBox(width: 76, child: TextField(controller: _icon, textAlign: TextAlign.center, decoration: const InputDecoration(labelText: 'أيقونة'))),
              const SizedBox(width: 10),
              Expanded(child: TextField(controller: _label, decoration: const InputDecoration(labelText: 'اسم الحساب', hintText: 'مثل: تطبيق التواصل'))),
            ]),
            const SizedBox(height: 14),
            if (sa) ...[
              OutlinedButton.icon(
                onPressed: _busy ? null : _pick,
                icon: Icon(_fileName == null ? Icons.upload_file_rounded : Icons.check_circle_rounded,
                    color: _fileName == null ? null : Brand.success),
                label: Text(_fileName ?? 'اختر ملف المفتاح (.json)'),
              ),
              const SizedBox(height: 8),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: const Text('أو الصق محتوى الملف', style: TextStyle(fontSize: 14)),
                children: [
                  TextField(
                    controller: _json,
                    maxLines: 6,
                    textDirection: TextDirection.ltr,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                    decoration: const InputDecoration(hintText: '{ "type": "service_account", ... }'),
                  ),
                ],
              ),
            ] else ...[
              TextField(controller: _projectId, textDirection: TextDirection.ltr, decoration: const InputDecoration(labelText: 'معرّف المشروع (Project ID)')),
              const SizedBox(height: 12),
              TextField(controller: _apiKey, textDirection: TextDirection.ltr, decoration: const InputDecoration(labelText: 'مفتاح Web API')),
              const SizedBox(height: 12),
              TextField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                textDirection: TextDirection.ltr,
                decoration: const InputDecoration(labelText: 'إيميل المشرف', prefixIcon: Icon(Icons.mail_outline)),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _password,
                obscureText: _hide,
                textDirection: TextDirection.ltr,
                decoration: InputDecoration(
                  labelText: 'كلمة المرور',
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    icon: Icon(_hide ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                    onPressed: () => setState(() => _hide = !_hide),
                  ),
                ),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Brand.danger.withValues(alpha: .1), borderRadius: BorderRadius.circular(12)),
                child: Text(_error!, style: const TextStyle(color: Brand.danger, height: 1.5)),
              ),
            ],
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _busy ? null : _save,
              icon: _busy
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.link_rounded),
              label: const Text('ربط الحساب'),
            ),
            TextButton.icon(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => SetupGuideScreen(serviceAccount: sa))),
              icon: const Icon(Icons.help_outline_rounded),
              label: Text(sa ? 'من وين أجيب ملف حساب الخدمة؟' : 'من وين أجيب هذي البيانات؟'),
            ),
          ]),
        ),
      ),
    );
  }
}
