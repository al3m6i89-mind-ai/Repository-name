import 'package:flutter/material.dart';

import '../backend/backend.dart';
import '../backend/demo_backend.dart';
import '../config.dart';
import 'apps_screen.dart';

class LoginScreen extends StatefulWidget {
  final HubConfig config;
  const LoginScreen({super.key, required this.config});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  late final _email = TextEditingController(text: widget.config.lastEmail);
  final _password = TextEditingController();
  late final _apiKey = TextEditingController(text: widget.config.apiKey);
  late final _projectId = TextEditingController(text: widget.config.projectId);
  late bool _demo = widget.config.demo;
  bool _busy = false;
  bool _hide = true;
  String? _error;

  @override
  void dispose() {
    for (final c in [_email, _password, _apiKey, _projectId]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _signIn() async {
    final c = widget.config
      ..demo = _demo
      ..apiKey = _apiKey.text.trim()
      ..projectId = _projectId.text.trim()
      ..lastEmail = _email.text.trim();
    if (!_demo && !c.firebaseReady) {
      return setState(() => _error = 'اكتب مفتاح Web API ومعرّف المشروع من إعدادات Firebase');
    }
    if (_email.text.trim().isEmpty || _password.text.isEmpty) {
      return setState(() => _error = 'اكتب الإيميل وكلمة المرور');
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final backend = c.createBackend();
    try {
      await backend.signIn(_email.text, _password.text);
      await c.save();
      if (!mounted) return;
      _password.clear();
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => AppsScreen(backend: backend, config: c)));
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
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: ListView(
              padding: const EdgeInsets.all(24),
              shrinkWrap: true,
              children: [
                CircleAvatar(
                  radius: 40,
                  backgroundColor: cs.primaryContainer,
                  child: Icon(Icons.admin_panel_settings, size: 44, color: cs.onPrimaryContainer),
                ),
                const SizedBox(height: 16),
                Text('لوحة تطبيقاتي', textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineMedium),
                const SizedBox(height: 6),
                Text('ادخل بإيميلك وكلمة المرور لإدارة مستخدمي تطبيقاتك',
                    textAlign: TextAlign.center, style: TextStyle(color: cs.onSurfaceVariant)),
                const SizedBox(height: 24),
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: true, label: Text('تجريبي'), icon: Icon(Icons.science_outlined)),
                    ButtonSegment(value: false, label: Text('Firebase'), icon: Icon(Icons.cloud_outlined)),
                  ],
                  selected: {_demo},
                  onSelectionChanged: (s) => setState(() {
                    _demo = s.first;
                    _error = null;
                  }),
                ),
                const SizedBox(height: 16),
                if (_demo)
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.info_outline),
                      title: const Text('بيانات وهمية للتجربة'),
                      subtitle: const Text('${DemoBackend.demoEmail}\nكلمة المرور: ${DemoBackend.demoPassword}'),
                      isThreeLine: true,
                      trailing: TextButton(
                        onPressed: () => setState(() {
                          _email.text = DemoBackend.demoEmail;
                          _password.text = DemoBackend.demoPassword;
                        }),
                        child: const Text('عبّئ'),
                      ),
                    ),
                  )
                else ...[
                  TextField(
                    controller: _projectId,
                    textDirection: TextDirection.ltr,
                    decoration: const InputDecoration(labelText: 'معرّف المشروع (Project ID)', hintText: 'my-apps-12345'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _apiKey,
                    textDirection: TextDirection.ltr,
                    decoration: const InputDecoration(labelText: 'مفتاح Web API', hintText: 'AIza…'),
                  ),
                ],
                const SizedBox(height: 16),
                TextField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  textDirection: TextDirection.ltr,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(labelText: 'الإيميل', prefixIcon: Icon(Icons.email_outlined)),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _password,
                  obscureText: _hide,
                  textDirection: TextDirection.ltr,
                  onSubmitted: (_) => _busy ? null : _signIn(),
                  decoration: InputDecoration(
                    labelText: 'كلمة المرور',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      icon: Icon(_hide ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                      onPressed: () => setState(() => _hide = !_hide),
                    ),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: TextStyle(color: cs.error)),
                ],
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: _busy ? null : _signIn,
                  icon: _busy
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.login),
                  label: const Text('دخول'),
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
