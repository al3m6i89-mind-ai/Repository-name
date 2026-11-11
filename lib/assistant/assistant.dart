import '../backend/actions.dart';
import '../backend/models.dart';
import '../backend/session.dart';
import '../ui/widgets.dart' show statusName;

/// Something the assistant offers to do once the admin confirms.
class PendingAction {
  final String label;
  final bool danger;
  final Future<String> Function() run;
  const PendingAction(this.label, this.run, {this.danger = false});
}

class AssistantReply {
  final String text;
  final List<(AppInfo, AppUser)> users;
  final List<String> suggestions;
  final PendingAction? action;
  const AssistantReply(this.text, {this.users = const [], this.suggestions = const [], this.action});
}

/// Understands short Arabic questions and commands about the hub's data.
/// Runs entirely on the device, so every answer is instant.
class Assistant {
  final HubSession session;
  Assistant(this.session);

  static const helpSuggestions = [
    'ملخص اليوم',
    'كم مستخدم عندي؟',
    'مين سجل اليوم؟',
    'مين المحظورين؟',
    'كم واحد متصل الآن؟',
    'ابحث عن ',
  ];

  /// Lower-cases and folds Arabic letter variants so matching is forgiving.
  static String norm(String s) {
    const digits = {'٠': '0', '١': '1', '٢': '2', '٣': '3', '٤': '4', '٥': '5', '٦': '6', '٧': '7', '٨': '8', '٩': '9'};
    final b = StringBuffer();
    for (final ch in s.toLowerCase().split('')) {
      b.write(switch (ch) {
        'أ' || 'إ' || 'آ' => 'ا',
        'ة' => 'ه',
        'ى' => 'ي',
        'ؤ' => 'و',
        'ئ' => 'ي',
        '؟' || '?' || '!' || '،' || ',' || '.' => ' ',
        _ => digits[ch] ?? ch,
      });
    }
    return b
        .toString()
        .replaceAll(RegExp('[ً-ْـ]'), '') // harakat and tatweel
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static bool _has(String n, List<String> words) => words.any(n.contains);

  List<(AppInfo, AppUser)> _all(AppInfo? only) => [
        for (final d in session.apps)
          if (only == null || d.app.key == only.key)
            for (final u in d.users) (d.app, u),
      ];

  AppInfo? _appIn(String n) {
    for (final d in session.apps) {
      final name = norm(d.app.name);
      if (name.length >= 2 && n.contains(name)) return d.app;
    }
    return null;
  }

  AssistantReply answer(String input) {
    final n = norm(input);
    if (session.apps.isEmpty) {
      return const AssistantReply('ما عندي بيانات بعد. اربط حساب Firebase من صفحة التطبيقات، أو اسحب الصفحة للتحديث.');
    }
    final app = _appIn(n);
    final action = _action(n, input, app);
    if (action != null) return action;

    if (n.isEmpty || n.split(' ').length <= 4 && _has(n, ['مساعد', 'ساعدني', 'وش تقدر', 'ايش تقدر', 'وش تسوي', 'help', 'مرحبا', 'هلا', 'السلام'])) {
      return const AssistantReply(
        'أهلاً 👋 أنا مساعدك في اللوحة وأرد فوراً. جرّب تسألني عن الأعداد، أو تطلب مني أبحث عن حساب، أو تقول مثلاً «احظر أحمد» أو «احجب سارة 3 أيام» أو «ارسل لخالد: أهلاً بك».',
        suggestions: helpSuggestions,
      );
    }

    if (_has(n, ['ملخص', 'تقرير', 'احصاي', 'نظره عامه', 'وش الوضع', 'الوضع'])) return _summary(app);
    if (_has(n, ['كم تطبيق', 'عدد التطبيقات', 'تطبيقاتي', 'التطبيقات'])) return _apps();

    final filter = _filter(n);
    if (_has(n, ['كم', 'عدد'])) {
      final list = _all(app).where((p) => filter.$2(p.$2)).toList();
      return AssistantReply(
        '${app == null ? '' : 'في ${app.name}: '}عندك ${list.length} ${filter.$1}.',
        users: list.length <= 5 ? list : const [],
        suggestions: ['مين ${filter.$1}؟', 'ملخص اليوم'],
      );
    }
    if (_has(n, ['مين', 'من هم', 'اعرض', 'ورني', 'وريني', 'قايمه', 'عطني', 'اعطني', 'هات'])) {
      final list = _all(app).where((p) => filter.$2(p.$2)).toList()
        ..sort((a, b) => (b.$2.lastSeen ?? DateTime(0)).compareTo(a.$2.lastSeen ?? DateTime(0)));
      if (list.isEmpty) return AssistantReply('ما فيه أحد ${filter.$1} حالياً.');
      return AssistantReply(
        '${list.length} ${filter.$1}${list.length > 20 ? '، هذي أول 20' : ''}:',
        users: list.take(20).toList(),
      );
    }

    final term = _stripWords(n, ['ابحث عن', 'ابحث', 'دور على', 'دور', 'وين', 'حساب', 'بيانات', 'معلومات', 'المستخدم', 'عن']);
    final found = _find(term, app);
    if (found.isNotEmpty) {
      return AssistantReply(
        found.length == 1 ? 'لقيته 👇' : 'لقيت ${found.length} حساب${found.length > 20 ? '، هذي أول 20' : ''}:',
        users: found.take(20).toList(),
      );
    }
    return AssistantReply(
      'ما فهمت قصدك، أو ما لقيت حساب بهذا الاسم. جرّب صيغة من هذي:',
      suggestions: helpSuggestions,
    );
  }

  /// (label, test) for the group of users the question is about.
  (String, bool Function(AppUser)) _filter(String n) {
    final now = DateTime.now();
    final today = _has(n, ['اليوم', 'امس']) ? 1 : (_has(n, ['الاسبوع', 'اسبوع']) ? 7 : (_has(n, ['الشهر', 'شهر']) ? 30 : 0));
    bool within(DateTime? d, int days) => d != null && now.difference(d).inDays < days;
    if (_has(n, ['محظور', 'المحظورين', 'حظرت'])) return ('محظور', (u) => u.status == UserStatus.banned);
    if (_has(n, ['محجوب', 'المحجوبين', 'معلق'])) return ('محجوب', (u) => u.status == UserStatus.suspended);
    if (_has(n, ['مقيد', 'المقيدين'])) return ('مقيّد', (u) => u.status == UserStatus.restricted);
    if (_has(n, ['متصل', 'اونلاين', 'online', 'الحين', 'الان'])) return ('متصل الآن', (u) => u.onlineRecently);
    if (_has(n, ['سجل', 'جديد', 'الجدد', 'انضم', 'دخلوا جديد'])) {
      final days = today == 0 ? 7 : today;
      return (days == 1 ? 'سجّل اليوم' : 'سجّل آخر $days أيام', (u) => within(u.createdAt, days));
    }
    if (_has(n, ['نشط', 'النشطين', 'فاعل', 'دخل'])) {
      final days = today == 0 ? 1 : today;
      return (days == 1 ? 'نشط اليوم' : 'نشط آخر $days أيام', (u) => within(u.lastSeen, days));
    }
    if (_has(n, ['موثق', 'الموثقين'])) return ('موثّق', (u) => u.verified);
    if (_has(n, ['vip', 'مميز'])) return ('مميز VIP', (u) => u.role == 'vip');
    if (_has(n, ['مشرف'])) return ('مشرف محتوى', (u) => u.role == 'moderator');
    if (_has(n, ['max'])) return ('مشترك Max', (u) => u.plan == 'max');
    if (_has(n, ['pro', 'برو'])) return ('مشترك Pro', (u) => u.plan == 'pro');
    if (_has(n, ['مجاني'])) return ('على الخطة المجانية', (u) => u.plan == 'free');
    if (_has(n, ['تحذير', 'محذر'])) return ('عنده تحذيرات', (u) => u.warnings > 0);
    return ('مستخدم', (_) => true);
  }

  AssistantReply _summary(AppInfo? app) {
    final all = _all(app).map((p) => p.$2).toList();
    final now = DateTime.now();
    int c(bool Function(AppUser) f) => all.where(f).length;
    final lines = [
      '📊 ${app == null ? 'ملخص كل التطبيقات' : 'ملخص ${app.name}'}',
      '• المستخدمين: ${all.length}',
      '• متصل الآن: ${c((u) => u.onlineRecently)}',
      '• نشط اليوم: ${c((u) => u.lastSeen != null && now.difference(u.lastSeen!).inHours < 24)}',
      '• سجّل اليوم: ${c((u) => u.createdAt != null && now.difference(u.createdAt!).inHours < 24)}',
      '• سجّل هذا الأسبوع: ${c((u) => u.createdAt != null && now.difference(u.createdAt!).inDays < 7)}',
      for (final s in [UserStatus.banned, UserStatus.suspended, UserStatus.restricted]) '• ${statusName(s)}: ${c((u) => u.status == s)}',
    ];
    if (app == null && session.apps.length > 1) {
      final top = [...session.apps]..sort((a, b) => b.users.length.compareTo(a.users.length));
      lines.add('• الأكبر: ${top.first.app.icon} ${top.first.app.name} (${top.first.users.length})');
    }
    return AssistantReply(lines.join('\n'), suggestions: const ['مين سجل اليوم؟', 'مين المحظورين؟', 'مين متصل الآن؟']);
  }

  AssistantReply _apps() => AssistantReply(
        'عندك ${session.apps.length} تطبيق:\n${session.apps.map((d) => '${d.app.icon} ${d.app.name}: ${d.users.length} مستخدم').join('\n')}',
        suggestions: [for (final d in session.apps.take(3)) 'ملخص ${d.app.name}'],
      );

  static String _stripWords(String n, List<String> words) {
    var t = ' $n ';
    for (final w in words) {
      t = t.replaceAll(' $w ', ' ');
    }
    return t.trim();
  }

  List<(AppInfo, AppUser)> _find(String term, AppInfo? app) {
    final t = norm(term);
    if (t.length < 2) return const [];
    final out = <(AppInfo, AppUser)>[];
    for (final p in _all(app)) {
      final u = p.$2;
      final hay = norm('${u.name} ${u.email} ${u.phone} ${u.id}');
      if (hay.contains(t) || t.split(' ').where((w) => w.length >= 3).every(hay.contains) && t.contains(' ')) out.add(p);
    }
    return out;
  }

  // Commands -------------------------------------------------------------------

  AssistantReply? _action(String n, String raw, AppInfo? app) {
    String? verb;
    if (_has(n, ['فك الحظر', 'فك حظر', 'الغ الحظر', 'شيل الحظر', 'رفع الحظر'])) {
      verb = 'unban';
    } else if (_has(n, ['فك الحجب', 'رفع الحجب', 'الغ الحجب', 'شيل الحجب'])) {
      verb = 'unsuspend';
    } else if (RegExp(r'(^| )(احظر|حظر|ابند|بند)( |$)').hasMatch(n)) {
      verb = 'ban';
    } else if (RegExp(r'(^| )(احجب|حجب|علق)( |$)').hasMatch(n)) {
      verb = 'suspend';
    } else if (_has(n, ['ارسل', 'راسل', 'رسل', 'قول ل'])) {
      verb = 'message';
    } else if (_has(n, ['حذر', 'نبه'])) {
      verb = 'warn';
    } else if (_has(n, ['اطرد', 'سجل خروج', 'خرج'])) {
      verb = 'logout';
    } else if (RegExp(r'(^| )(وثق)( |$)').hasMatch(n)) {
      verb = 'verify';
    } else if (RegExp(r'(^| )(احذف|امسح)( |$)').hasMatch(n) && !_has(n, ['منشور', 'قصه'])) {
      verb = 'delete';
    }
    if (verb == null) return null;

    // "ارسل لأحمد: نص" / "احجب سارة 3 ايام"
    var text = '';
    var target = n;
    final colon = raw.indexOf(RegExp('[:：]'));
    if (colon > 0) {
      text = raw.substring(colon + 1).trim();
      target = norm(raw.substring(0, colon));
    }
    Duration? dur;
    final m = RegExp(r'(\d+)\s*(يوم|ايام|ساعه|ساعات|اسبوع|اسابيع|شهر|اشهر|دقيقه|دقايق)').firstMatch(target);
    if (m != null) {
      final k = int.parse(m.group(1)!);
      final unit = m.group(2)!;
      dur = unit.startsWith('ساع')
          ? Duration(hours: k)
          : unit.startsWith('دق')
              ? Duration(minutes: k)
              : unit.contains('سب')
                  ? Duration(days: 7 * k)
                  : unit.contains('شهر')
                      ? Duration(days: 30 * k)
                      : Duration(days: k);
      target = target.replaceAll(m.group(0)!, ' ');
    } else if (_has(target, ['يوم'])) {
      dur = const Duration(days: 1);
    } else if (_has(target, ['اسبوع'])) {
      dur = const Duration(days: 7);
    } else if (_has(target, ['ساعه'])) {
      dur = const Duration(hours: 1);
    }
    final who = _stripWords(target, [
      'فك الحظر', 'فك حظر', 'الغ الحظر', 'شيل الحظر', 'رفع الحظر', 'فك الحجب', 'رفع الحجب', 'الغ الحجب', 'شيل الحجب',
      'احظر', 'حظر', 'ابند', 'بند', 'احجب', 'حجب', 'علق', 'ارسل', 'راسل', 'رسل', 'رساله', 'حذر', 'نبه', 'اطرد', 'سجل خروج',
      'خرج', 'وثق', 'احذف', 'امسح', 'حساب', 'المستخدم', 'عن', 'من', 'لمده', 'مده', 'يوم', 'اسبوع', 'ساعه', 'عن', 'في',
      if (app != null) norm(app.name),
    ]).replaceAll(RegExp(r'(^| )ل(?=\S)'), ' ').trim();

    final found = _find(who, app);
    if (who.length < 2) return const AssistantReply('مين المستخدم؟ اكتب اسمه أو إيميله، مثل: «احظر أحمد».');
    if (found.isEmpty) return AssistantReply('ما لقيت حساب باسم «$who».');
    if (found.length > 1) {
      return AssistantReply('لقيت ${found.length} حسابات بهذا الاسم. حدد أكثر (مثل الإيميل)، أو افتح الحساب من هنا:', users: found.take(10).toList());
    }
    final (a, u) = found.single;
    final acts = UserActions(session.backendOf(a));
    final name = u.displayName;
    Future<String> done(Future<void> f, String ok) async {
      await f;
      final fresh = await session.backendOf(a).getUser(a.id, u.id);
      if (fresh != null) session.putUser(a, fresh);
      return ok;
    }

    final PendingAction act;
    switch (verb) {
      case 'ban':
        act = PendingAction('حظر $name', () => done(acts.ban(a.id, u, text), 'تم حظر $name ✓'), danger: true);
      case 'unban':
        act = PendingAction('فك حظر $name', () => done(acts.unban(a.id, u), 'تم فك حظر $name ✓'));
      case 'suspend':
        final d = dur ?? const Duration(days: 1);
        final label = d.inDays >= 1 ? '${d.inDays} يوم' : (d.inHours >= 1 ? '${d.inHours} ساعة' : '${d.inMinutes} دقيقة');
        act = PendingAction('حجب $name لمدة $label',
            () => done(acts.suspend(a.id, u, DateTime.now().add(d), text), 'تم حجب $name $label ✓'), danger: true);
      case 'unsuspend':
        act = PendingAction('رفع الحجب عن $name', () => done(acts.unsuspend(a.id, u), 'تم رفع الحجب ✓'));
      case 'message':
        if (text.isEmpty) return AssistantReply('وش الرسالة؟ اكتبها بعد نقطتين، مثل: «ارسل ل$name: أهلاً بك»', users: [found.single]);
        act = PendingAction('إرسال «$text» إلى $name', () => acts.message(a.id, u, text));
      case 'warn':
        if (text.isEmpty) return AssistantReply('وش سبب التحذير؟ مثل: «حذر $name: ممنوع السبام»', users: [found.single]);
        act = PendingAction('تحذير $name: «$text»', () => acts.warn(a.id, u, text));
      case 'logout':
        act = PendingAction('تسجيل خروج $name من كل الأجهزة', () => done(acts.forceLogout(a.id, u), 'تم تسجيل خروجه ✓'));
      case 'verify':
        act = PendingAction('توثيق $name', () => done(acts.setVerified(a.id, u, true), 'تم التوثيق ✓'));
      default:
        act = PendingAction('حذف حساب $name نهائياً', () async {
          await acts.delete(a.id, u);
          session.dropUser(a, u.id);
          return 'تم حذف $name';
        }, danger: true);
    }
    return AssistantReply('أأكد؟ ${act.label}${text.isNotEmpty && verb != 'message' && verb != 'warn' ? ' (السبب: $text)' : ''}',
        users: [found.single], action: act);
  }
}
