import 'backend.dart';
import 'models.dart';

/// Sample data kept in memory, so the hub can be tried with no setup.
class DemoBackend implements AdminBackend {
  static const demoEmail = 'admin@demo.com';
  static const demoPassword = '123456';

  String? _email;
  final List<AppInfo> _apps = [
    const AppInfo(id: 'shop', name: 'متجري', icon: '🛍️', description: 'تطبيق تجريبي'),
    const AppInfo(id: 'notes', name: 'ملاحظاتي', icon: '📝', description: 'تطبيق تجريبي'),
  ];
  late final Map<String, List<AppUser>> _users = {
    'shop': _sample(['أحمد علي', 'سارة محمد', 'خالد العتيبي', 'نورة القحطاني', 'فهد الشمري', 'ريم الزهراني', 'عبدالله الحربي']),
    'notes': _sample(['محمد سالم', 'هند يوسف', 'ماجد ناصر']),
  };

  static List<AppUser> _sample(List<String> names) {
    final now = DateTime.now();
    return [
      for (var i = 0; i < names.length; i++)
        AppUser(
          id: 'u${i + 1}',
          name: names[i],
          email: 'user${i + 1}@example.com',
          createdAt: now.subtract(Duration(days: 40 - i * 5)),
          lastSeen: now.subtract(Duration(hours: i * 7)),
          banned: i == 4,
          banReason: i == 4 ? 'مخالفة الشروط' : '',
          suspendedUntil: i == 2 ? now.add(const Duration(days: 3)) : null,
          extra: {'الخطة': i.isEven ? 'مجاني' : 'Pro', 'النقاط': '${(i + 1) * 35}'},
        ),
    ];
  }

  @override
  String get label => 'وضع تجريبي';

  @override
  String? get adminEmail => _email;

  @override
  Future<void> signIn(String email, String password) async {
    await Future.delayed(const Duration(milliseconds: 300));
    if (email.trim().toLowerCase() != demoEmail || password != demoPassword) {
      throw BackendError('في الوضع التجريبي استخدم $demoEmail وكلمة المرور $demoPassword');
    }
    _email = demoEmail;
  }

  @override
  Future<void> signOut() async => _email = null;

  @override
  Future<List<AppInfo>> listApps() async => List.of(_apps);

  @override
  Future<void> saveApp(AppInfo app) async {
    _apps.removeWhere((a) => a.id == app.id);
    _apps.add(app);
    _users.putIfAbsent(app.id, () => []);
  }

  @override
  Future<void> deleteApp(String appId) async {
    _apps.removeWhere((a) => a.id == appId);
    _users.remove(appId);
  }

  @override
  Future<List<AppUser>> listUsers(String appId) async {
    await Future.delayed(const Duration(milliseconds: 200));
    return List.of(_users[appId] ?? const []);
  }

  void _edit(String appId, String userId, AppUser Function(AppUser) f) {
    final list = _users[appId];
    if (list == null) return;
    final i = list.indexWhere((u) => u.id == userId);
    if (i >= 0) list[i] = f(list[i]);
  }

  @override
  Future<void> deleteUser(String appId, String userId) async => _users[appId]?.removeWhere((u) => u.id == userId);

  @override
  Future<void> setBanned(String appId, String userId, bool banned, {String reason = ''}) async =>
      _edit(appId, userId, (u) => u.copyWith(banned: banned, banReason: banned ? reason : ''));

  @override
  Future<void> setSuspendedUntil(String appId, String userId, DateTime? until, {String reason = ''}) async =>
      _edit(appId, userId, (u) => u.copyWith(suspendedUntil: until, clearSuspension: until == null, banReason: reason));
}
