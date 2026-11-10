import 'package:flutter/material.dart';

import '../backend/actions.dart';
import '../backend/models.dart';
import 'theme.dart';

const avatarColors = [
  Color(0xFF6366F1), Color(0xFF8B5CF6), Color(0xFFEC4899), Color(0xFFF59E0B),
  Color(0xFF10B981), Color(0xFF0EA5E9), Color(0xFFEF4444), Color(0xFF14B8A6),
];

class UserAvatar extends StatelessWidget {
  final AppUser user;
  final double size;
  const UserAvatar({super.key, required this.user, this.size = 44});

  @override
  Widget build(BuildContext context) {
    final c = avatarColors[user.id.hashCode.abs() % avatarColors.length];
    final letter = user.displayName.characters.first;
    return Stack(clipBehavior: Clip.none, children: [
      Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [c, Color.lerp(c, Colors.black, .2)!]),
          borderRadius: BorderRadius.circular(size * .32),
        ),
        child: Text(letter, style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: size * .42)),
      ),
      if (user.onlineRecently)
        PositionedDirectional(
          bottom: -1,
          end: -1,
          child: Container(
            width: size * .3,
            height: size * .3,
            decoration: BoxDecoration(
              color: Brand.success,
              shape: BoxShape.circle,
              border: Border.all(color: Theme.of(context).cardTheme.color ?? Colors.white, width: 2),
            ),
          ),
        ),
    ]);
  }
}

(Color, String) statusLook(AppUser u) => switch (u.status) {
      UserStatus.active => (Brand.success, 'نشط'),
      UserStatus.restricted => (Brand.info, 'مقيّد'),
      UserStatus.suspended => (Brand.warning, 'محجوب ${fmtLeft(u.suspendedUntil!)}'),
      UserStatus.banned => (Brand.danger, 'محظور'),
    };

String statusName(UserStatus s) => switch (s) {
      UserStatus.active => 'نشط',
      UserStatus.restricted => 'مقيّد',
      UserStatus.suspended => 'محجوب',
      UserStatus.banned => 'محظور',
    };

class Pill extends StatelessWidget {
  final String text;
  final Color color;
  final IconData? icon;
  const Pill(this.text, {super.key, required this.color, this.icon});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(color: color.withValues(alpha: .13), borderRadius: BorderRadius.circular(20)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[Icon(icon, size: 13, color: color), const SizedBox(width: 4)],
          Text(text, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700, height: 1.2)),
        ]),
      );
}

class StatusPill extends StatelessWidget {
  final AppUser user;
  const StatusPill({super.key, required this.user});

  @override
  Widget build(BuildContext context) {
    final (c, t) = statusLook(user);
    return Pill(t, color: c);
  }
}

class StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;
  const StatCard({super.key, required this.label, required this.value, required this.icon, required this.color, this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: color.withValues(alpha: .13), borderRadius: BorderRadius.circular(12)),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(height: 12),
            Text(value, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, height: 1)),
            const SizedBox(height: 4),
            Text(label, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis),
          ]),
        ),
      ),
    );
  }
}

class SectionTitle extends StatelessWidget {
  final String text;
  final Widget? trailing;
  const SectionTitle(this.text, {super.key, this.trailing});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 20, 4, 10),
        child: Row(children: [
          Expanded(child: Text(text, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800))),
          if (trailing != null) trailing!,
        ]),
      );
}

class AppBadge extends StatelessWidget {
  final AppInfo app;
  final double size;
  const AppBadge({super.key, required this.app, this.size = 48});

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: .6),
          borderRadius: BorderRadius.circular(size * .3),
        ),
        child: Text(app.icon, style: TextStyle(fontSize: size * .5)),
      );
}

class ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const ErrorView({super.key, required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: Brand.danger.withValues(alpha: .12), shape: BoxShape.circle),
              child: const Icon(Icons.cloud_off_rounded, size: 36, color: Brand.danger),
            ),
            const SizedBox(height: 14),
            Text(message, textAlign: TextAlign.center, style: const TextStyle(height: 1.5)),
            const SizedBox(height: 14),
            OutlinedButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh), label: const Text('إعادة المحاولة')),
          ]),
        ),
      );
}

class EmptyView extends StatelessWidget {
  final IconData icon;
  final String title;
  final String text;
  final Widget? action;
  const EmptyView({super.key, required this.icon, required this.title, this.text = '', this.action});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(color: cs.primaryContainer.withValues(alpha: .5), shape: BoxShape.circle),
            child: Icon(icon, size: 36, color: cs.primary),
          ),
          const SizedBox(height: 14),
          Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800), textAlign: TextAlign.center),
          if (text.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(text, textAlign: TextAlign.center, style: TextStyle(color: cs.onSurfaceVariant, height: 1.5)),
          ],
          if (action != null) ...[const SizedBox(height: 16), action!],
        ]),
      ),
    );
  }
}

Future<bool> confirm(BuildContext context, String title, String body, {String action = 'تأكيد', bool danger = true}) async {
  return await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
          content: Text(body, style: const TextStyle(height: 1.5)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
            FilledButton(
              style: danger ? FilledButton.styleFrom(backgroundColor: Brand.danger, foregroundColor: Colors.white) : null,
              onPressed: () => Navigator.pop(context, true),
              child: Text(action),
            ),
          ],
        ),
      ) ??
      false;
}

/// Asks for one line of text. Returns null on cancel.
Future<String?> askText(BuildContext context, String title,
    {String label = '', String initial = '', bool required = false, int maxLines = 1, TextInputType? keyboard}) async {
  final c = TextEditingController(text: initial);
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
      content: TextField(
        controller: c,
        autofocus: true,
        maxLines: maxLines,
        keyboardType: keyboard,
        decoration: InputDecoration(labelText: label),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
        FilledButton(
          onPressed: () {
            if (required && c.text.trim().isEmpty) return;
            Navigator.pop(ctx, true);
          },
          child: const Text('تأكيد'),
        ),
      ],
    ),
  );
  final text = c.text.trim();
  c.dispose();
  return ok == true ? text : null;
}

void toast(BuildContext context, String text, {bool error = false}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(text),
      backgroundColor: error ? Brand.danger : null,
    ));
}
