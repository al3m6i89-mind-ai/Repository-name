import 'package:flutter/material.dart';

import '../backend/models.dart';

String durationLabel(Duration d) {
  if (d.inDays >= 1) return '${d.inDays} يوم';
  if (d.inHours >= 1) return '${d.inHours} ساعة';
  return '${d.inMinutes} دقيقة';
}

/// Picks how long a suspension lasts.
Future<Duration?> pickDuration(BuildContext context) =>
    showDialog<Duration>(context: context, builder: (_) => const _DurationDialog());

class _DurationDialog extends StatefulWidget {
  const _DurationDialog();

  @override
  State<_DurationDialog> createState() => _DurationDialogState();
}

class _DurationDialogState extends State<_DurationDialog> {
  final _n = TextEditingController();
  bool _hours = false;
  static const presets = [
    Duration(hours: 1),
    Duration(hours: 6),
    Duration(hours: 24),
    Duration(days: 3),
    Duration(days: 7),
    Duration(days: 30),
  ];

  @override
  void dispose() {
    _n.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('مدة الحجب', style: TextStyle(fontWeight: FontWeight.w800)),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final d in presets) ActionChip(label: Text(durationLabel(d)), onPressed: () => Navigator.pop(context, d)),
        ]),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(
            child: TextField(
              controller: _n,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'مدة مخصصة'),
            ),
          ),
          const SizedBox(width: 8),
          SegmentedButton<bool>(
            showSelectedIcon: false,
            segments: const [ButtonSegment(value: false, label: Text('يوم')), ButtonSegment(value: true, label: Text('ساعة'))],
            selected: {_hours},
            onSelectionChanged: (v) => setState(() => _hours = v.first),
          ),
        ]),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
        FilledButton(
          onPressed: () {
            final n = int.tryParse(_n.text.trim());
            if (n != null && n > 0) Navigator.pop(context, _hours ? Duration(hours: n) : Duration(days: n));
          },
          child: const Text('حجب'),
        ),
      ],
    );
  }
}

/// Picks which features to switch off.
Future<List<String>?> pickRestrictions(BuildContext context, List<String> current) =>
    showDialog<List<String>>(context: context, builder: (_) => _RestrictDialog(current));

class _RestrictDialog extends StatefulWidget {
  final List<String> current;
  const _RestrictDialog(this.current);

  @override
  State<_RestrictDialog> createState() => _RestrictDialogState();
}

class _RestrictDialogState extends State<_RestrictDialog> {
  late final Set<String> _sel = {...widget.current};

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('تقييد الميزات', style: TextStyle(fontWeight: FontWeight.w800)),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('المستخدم يقدر يدخل التطبيق، لكن الميزات المختارة تتقفل عليه.', style: TextStyle(height: 1.5)),
          const SizedBox(height: 8),
          for (final e in {...userFeatures, for (final k in widget.current) k: userFeatures[k] ?? k}.entries)
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _sel.contains(e.key),
              title: Text(e.value),
              onChanged: (v) => setState(() => v == true ? _sel.add(e.key) : _sel.remove(e.key)),
            ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
        FilledButton(onPressed: () => Navigator.pop(context, _sel.toList()), child: const Text('حفظ')),
      ],
    );
  }
}

/// Picks one value from a labelled map.
Future<String?> pickOne(BuildContext context, String title, Map<String, String> options, String current) =>
    showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
        children: [
          for (final e in options.entries)
            ListTile(
              leading: Icon(e.key == current ? Icons.radio_button_checked : Icons.radio_button_off,
                  color: e.key == current ? Theme.of(ctx).colorScheme.primary : null),
              title: Text(e.value),
              onTap: () => Navigator.pop(ctx, e.key),
            ),
        ],
      ),
    );
