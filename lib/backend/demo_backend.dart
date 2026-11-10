import 'dart:math';

import 'backend.dart';
import 'models.dart';

/// Sample data kept in memory, so the hub can be tried with no setup.
class DemoBackend implements AdminBackend {
  static const demoEmail = 'admin@demo.com';

  String? _email;
  final List<AppInfo> _apps = [
    const AppInfo(id: 'social', name: 'تواصل', icon: '💬', description: 'تواصل اجتماعي'),
    const AppInfo(id: 'shop', name: 'متجري', icon: '🛍️', description: 'متجر إلكتروني'),
    const AppInfo(id: 'notes', name: 'ملاحظاتي', icon: '📝', description: 'ملاحظات ومهام'),
    const AppInfo(id: 'fitness', name: 'لياقتي', icon: '🏃', description: 'تمارين ومتابعة'),
  ];
  late final Map<String, List<AppUser>> _users = {
    'social': _sample(4, ['شهد العتيبي', 'عمر الفيفي', 'رهف السالم', 'مشاري الدوسري', 'غلا القحطاني', 'نواف الحربي', 'جنى الشهراني', 'راكان البقمي', 'لين المالكي']),
    'shop': _sample(1, [
      'أحمد علي', 'سارة محمد', 'خالد العتيبي', 'نورة القحطاني', 'فهد الشمري', 'ريم الزهراني', 'عبدالله الحربي',
      'لمى الدوسري', 'تركي المطيري', 'جود الغامدي', 'سلطان العنزي', 'هيفاء السبيعي',
    ]),
    'notes': _sample(2, ['محمد سالم', 'هند يوسف', 'ماجد ناصر', 'دانة فيصل', 'يوسف الشهري']),
    'fitness': _sample(3, ['بدر العمري', 'أمل حسن', 'زياد الرشيد', 'منيرة الخالدي']),
  };
  final Map<String, String> _notes = {};
  final List<LogEntry> _logs = [];

  static List<AppUser> _sample(int seed, List<String> names) {
    final r = Random(seed);
    final now = DateTime.now();
    const devices = ['Samsung Galaxy S24', 'iPhone 15', 'Xiaomi 14', 'Huawei P60', 'Pixel 8'];
    return [
      for (var i = 0; i < names.length; i++)
        AppUser(
          id: 'u$seed${i + 1}',
          name: names[i],
          email: 'user$seed${i + 1}@example.com',
          phone: '+9665${r.nextInt(90000000) + 10000000}',
          createdAt: now.subtract(Duration(days: 2 + r.nextInt(90))),
          lastSeen: now.subtract(Duration(minutes: i == 0 ? 3 : r.nextInt(60 * 24 * 10))),
          device: devices[r.nextInt(devices.length)],
          appVersion: '1.${r.nextInt(4)}.0',
          banned: i == 4,
          banReason: i == 4 ? 'مخالفة شروط الاستخدام' : '',
          suspendedUntil: i == 2 ? now.add(const Duration(days: 3)) : null,
          role: i == 1 ? 'vip' : (i == 6 ? 'moderator' : 'user'),
          plan: ['free', 'free', 'pro', 'max'][r.nextInt(4)],
          points: r.nextInt(500),
          verified: r.nextBool(),
          restrictions: i == 3 ? const ['chat'] : const [],
          warnings: i == 3 ? 1 : 0,
          lastWarning: i == 3 ? 'ألفاظ غير لائقة' : '',
        ),
    ];
  }

  @override
  String get label => 'وضع تجريبي';

  @override
  bool get isDemo => true;

  @override
  String? get adminEmail => _email;

  @override
  Future<void> connect() async => _email = demoEmail;

  @override
  Map<String, String> get sessionData => const {};

  @override
  Future<List<AppInfo>> listApps() async => List.of(_apps);

  @override
  Future<void> saveApp(AppInfo app) async {
    final i = _apps.indexWhere((a) => a.id == app.id);
    i >= 0 ? _apps[i] = app : _apps.add(app);
    _users.putIfAbsent(app.id, () => []);
  }

  @override
  Future<void> deleteApp(String appId) async {
    _apps.removeWhere((a) => a.id == appId);
    _users.remove(appId);
  }

  @override
  Future<List<AppUser>> listUsers(String appId) async {
    await Future.delayed(const Duration(milliseconds: 150));
    return List.of(_users[appId] ?? const []);
  }

  @override
  Future<AppUser?> getUser(String appId, String userId) async {
    for (final u in _users[appId] ?? const <AppUser>[]) {
      if (u.id == userId) return u;
    }
    return null;
  }

  @override
  Future<void> updateUser(String appId, String userId, Map<String, Object?> changes) async {
    final list = _users[appId];
    final i = list?.indexWhere((u) => u.id == userId) ?? -1;
    if (i < 0) throw BackendError('المستخدم غير موجود');
    list![i] = list[i].apply(changes);
  }

  @override
  Future<void> deleteUser(String appId, String userId) async => _users[appId]?.removeWhere((u) => u.id == userId);

  @override
  Future<String> getNote(String appId, String userId) async => _notes['$appId/$userId'] ?? '';

  @override
  Future<void> setNote(String appId, String userId, String note) async => _notes['$appId/$userId'] = note;

  final Map<String, UserInsights> _insights = {};

  @override
  Future<UserInsights> getInsights(String appId, AppUser u) async {
    await Future.delayed(const Duration(milliseconds: 200));
    return _insights.putIfAbsent('$appId/${u.id}', () => _makeInsights(appId, u));
  }

  UserInsights _makeInsights(String appId, AppUser u) {
    final now = DateTime.now();
    final r = Random(u.id.hashCode);
    String pic(String tag) => 'https://picsum.photos/seed/${u.id}$tag/600/600';
    final data = <DataDoc>[
      DataDoc('users/${u.id}', {'name': u.name, 'email': u.email, 'city': 'الرياض', 'language': 'ar', 'notifications': true}),
    ];
    final events = <ActivityEvent>[
      ActivityEvent(at: u.lastSeen ?? now, title: 'فتح التطبيق', detail: u.device, icon: '📱'),
      ActivityEvent(at: u.createdAt ?? now, title: 'أنشأ الحساب', detail: u.email, icon: '🎉'),
    ];
    if (appId == 'social') {
      const captions = ['صباح الخير من الرياض ☀️', 'أجمل غروب شفته 🌅', 'قهوة اليوم ☕', 'مع الشباب في البر 🏕️', 'يوم رياضي 💪', 'جديد الأسبوع 📸'];
      for (var i = 0; i < 6; i++) {
        final at = now.subtract(Duration(hours: 5 + i * 20 + r.nextInt(10)));
        data.add(DataDoc('posts/p${u.id}$i', {
          'userId': u.id,
          'caption': captions[(i + r.nextInt(3)) % captions.length],
          'imageUrl': pic('p$i'),
          'likes': r.nextInt(300),
          'comments': r.nextInt(40),
          'createdAt': at,
        }));
        events.add(ActivityEvent(at: at, title: 'نشر منشوراً', detail: captions[i % captions.length], icon: '📝'));
      }
      for (var i = 0; i < 3; i++) {
        final at = now.subtract(Duration(hours: 1 + i * 6));
        data.add(DataDoc('stories/s${u.id}$i', {'uid': u.id, 'mediaUrl': pic('s$i'), 'views': r.nextInt(500), 'createdAt': at, 'expiresAt': at.add(const Duration(hours: 24))}));
        events.add(ActivityEvent(at: at, title: 'أضاف قصة', icon: '⏳'));
      }
      for (var i = 0; i < 2; i++) {
        final at = now.subtract(Duration(days: 1 + i * 3));
        data.add(DataDoc('moments/m${u.id}$i', {'ownerId': u.id, 'text': i == 0 ? 'لحظة لا تُنسى ✨' : 'ذكرى جميلة', 'videoUrl': pic('m$i'), 'createdAt': at}));
        events.add(ActivityEvent(at: at, title: 'شارك لحظة', icon: '✨'));
      }
      for (var i = 0; i < 3; i++) {
        final at = now.subtract(Duration(hours: 2 + i * 13));
        data.add(DataDoc('comments/c${u.id}$i', {'authorId': u.id, 'text': ['ما شاء الله 👏', 'رهيب!', 'وين المكان؟'][i], 'postId': 'p${r.nextInt(99)}', 'createdAt': at}));
        events.add(ActivityEvent(at: at, title: 'علّق على منشور', detail: ['ما شاء الله 👏', 'رهيب!', 'وين المكان؟'][i], icon: '💬'));
      }
      data.add(DataDoc('users/${u.id}/followers/list', {'count': r.nextInt(2000)}));
    } else {
      for (var i = 0; i < 3; i++) {
        final at = now.subtract(Duration(days: 1 + i * 4));
        data.add(DataDoc('users/${u.id}/orders/A${1000 + r.nextInt(9000)}', {'total': 50 + r.nextInt(400), 'status': ['تم التوصيل', 'قيد الشحن', 'جديد'][i], 'items': 1 + r.nextInt(4), 'createdAt': at}));
        events.add(ActivityEvent(at: at, title: 'أتم طلباً', detail: 'رقم ${1000 + i}', icon: '🧾'));
      }
      data.add(DataDoc('reviews/r${r.nextInt(900) + 100}', {'userId': u.id, 'rating': 5, 'text': 'خدمة ممتازة وسريعة', 'createdAt': now.subtract(const Duration(days: 2))}));
    }
    events.sort((a, b) => b.at.compareTo(a.at));
    return UserInsights(
      account: {
        'المعرّف (UID)': u.id,
        'طرق الدخول': 'إيميل وكلمة مرور، Google',
        'الإيميل موثّق': u.verified ? 'نعم' : 'لا',
        'الجهاز': u.device,
        'إصدار التطبيق': u.appVersion,
        'رقم الجوال': u.phone,
      },
      data: data,
      events: events,
    );
  }

  @override
  Future<void> deleteData(String path) async {
    for (final e in _insights.entries.toList()) {
      final i = e.value;
      _insights[e.key] = UserInsights(
        account: i.account,
        data: i.data.where((d) => d.path != path).toList(),
        events: i.events,
        notes: i.notes,
      );
    }
  }

  @override
  Future<void> addLog(LogEntry entry) async => _logs.insert(0, entry);

  @override
  Future<List<LogEntry>> listLogs({int limit = 200}) async => _logs.take(limit).toList();
}
