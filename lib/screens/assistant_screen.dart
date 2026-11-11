import 'package:flutter/material.dart';

import '../assistant/assistant.dart';
import '../backend/models.dart';
import '../main.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'user_detail_screen.dart';

class _Msg {
  final bool mine;
  final String text;
  final List<(AppInfo, AppUser)> users;
  final List<String> suggestions;
  PendingAction? action;
  String? actionResult;
  bool running = false;
  _Msg(this.mine, this.text, {this.users = const [], this.suggestions = const [], this.action});
}

/// Chat with the on-device assistant. Answers appear the moment you send.
class AssistantScreen extends StatefulWidget {
  const AssistantScreen({super.key});

  @override
  State<AssistantScreen> createState() => _AssistantScreenState();
}

class _AssistantScreenState extends State<AssistantScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _focus = FocusNode();
  final List<_Msg> _msgs = [];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_msgs.isEmpty) {
      final r = Assistant(Hub.of(context).session).answer('');
      _msgs.add(_Msg(false, r.text, suggestions: r.suggestions));
    }
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _send([String? text]) {
    final t = (text ?? _input.text).trim();
    if (t.isEmpty) return;
    if (text != null && text.endsWith(' ')) {
      // A suggestion that needs finishing, like "ابحث عن ".
      _input.text = text;
      _input.selection = TextSelection.collapsed(offset: text.length);
      _focus.requestFocus();
      return;
    }
    final r = Assistant(Hub.of(context).session).answer(t);
    setState(() {
      _msgs.add(_Msg(true, t));
      _msgs.add(_Msg(false, r.text, users: r.users, suggestions: r.suggestions, action: r.action));
      _input.clear();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      }
    });
  }

  Future<void> _confirm(_Msg m) async {
    setState(() => m.running = true);
    String result;
    try {
      result = await m.action!.run();
    } catch (e) {
      result = 'ما تم: $e';
    }
    if (!mounted) return;
    setState(() {
      m.running = false;
      m.actionResult = result;
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Row(children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: const BoxDecoration(gradient: Brand.gradient, shape: BoxShape.circle),
            child: const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 18),
          ),
          const SizedBox(width: 10),
          const Text('المساعد'),
        ]),
        actions: [
          IconButton(
            tooltip: 'محادثة جديدة',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => setState(_msgs.clear),
          ),
        ],
      ),
      body: Column(children: [
        Expanded(
          child: ListView.builder(
            controller: _scroll,
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
            itemCount: _msgs.length,
            itemBuilder: (_, i) => Appear(child: _bubble(_msgs[i], i == _msgs.length - 1)),
          ),
        ),
        SafeArea(
          top: false,
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
            decoration: BoxDecoration(
              color: Theme.of(context).cardTheme.color,
              border: Border(top: BorderSide(color: cs.outlineVariant.withValues(alpha: .4))),
            ),
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: _input,
                  focusNode: _focus,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _send(),
                  decoration: InputDecoration(
                    hintText: 'اسأل أو اطلب… مثل: كم محظور؟',
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(26)),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(26), borderSide: BorderSide(color: cs.outlineVariant)),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              DecoratedBox(
                decoration: const BoxDecoration(gradient: Brand.gradient, shape: BoxShape.circle),
                child: IconButton(
                  onPressed: _send,
                  icon: const Icon(Icons.arrow_upward_rounded, color: Colors.white),
                  tooltip: 'إرسال',
                ),
              ),
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _bubble(_Msg m, bool last) {
    final cs = Theme.of(context).colorScheme;
    final mine = m.mine;
    return Align(
      alignment: mine ? AlignmentDirectional.centerStart : AlignmentDirectional.centerEnd,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * .86),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                gradient: mine ? Brand.gradient : null,
                color: mine ? null : Theme.of(context).cardTheme.color,
                border: mine ? null : Border.all(color: cs.outlineVariant.withValues(alpha: .5)),
                borderRadius: BorderRadiusDirectional.only(
                  topStart: const Radius.circular(18),
                  topEnd: const Radius.circular(18),
                  bottomStart: Radius.circular(mine ? 4 : 18),
                  bottomEnd: Radius.circular(mine ? 18 : 4),
                ).resolve(Directionality.of(context)),
              ),
              child: SelectableText(m.text, style: TextStyle(color: mine ? Colors.white : null, height: 1.55, fontSize: 15)),
            ),
            for (final (app, u) in m.users)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Card(
                  clipBehavior: Clip.antiAlias,
                  child: ListTile(
                    dense: true,
                    leading: UserAvatar(user: u, size: 36),
                    title: Text(u.displayName, style: const TextStyle(fontWeight: FontWeight.w800)),
                    subtitle: Text('${app.icon} ${app.name} · ${u.email.isNotEmpty ? u.email : fmtAgoShort(u.lastSeen)}',
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    trailing: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 100), child: StatusPill(user: u)),
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => UserDetailScreen(app: app, user: u))),
                  ),
                ),
              ),
            if (m.action != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: m.actionResult != null
                    ? Pill(m.actionResult!, color: m.actionResult!.startsWith('ما تم') ? Brand.danger : Brand.success)
                    : Row(children: [
                        FilledButton(
                          style: m.action!.danger ? FilledButton.styleFrom(backgroundColor: Brand.danger, foregroundColor: Colors.white) : null,
                          onPressed: m.running ? null : () => _confirm(m),
                          child: m.running
                              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Text('نعم، نفّذ'),
                        ),
                        const SizedBox(width: 8),
                        TextButton(
                          onPressed: m.running ? null : () => setState(() => m.actionResult = 'أُلغي'),
                          child: const Text('إلغاء'),
                        ),
                      ]),
              ),
            if (last && m.suggestions.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Wrap(spacing: 6, runSpacing: 6, children: [
                  for (final s in m.suggestions) ActionChip(label: Text(s.trim()), onPressed: () => _send(s)),
                ]),
              ),
          ]),
        ),
      ),
    );
  }
}

String fmtAgoShort(DateTime? d) => d == null ? '' : 'آخر ظهور ${_ago(d)}';

String _ago(DateTime d) {
  final diff = DateTime.now().difference(d);
  if (diff.inMinutes < 60) return 'منذ ${diff.inMinutes.clamp(1, 59)} د';
  if (diff.inHours < 24) return 'منذ ${diff.inHours} س';
  return 'منذ ${diff.inDays} يوم';
}
