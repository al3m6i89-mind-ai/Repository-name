/// An app you built, whose users this hub manages.
class AppInfo {
  final String id;
  final String name;
  final String icon;
  final String description;

  /// Which connected account (Firebase project) this app belongs to.
  final String connectionId;

  const AppInfo({required this.id, required this.name, this.icon = '📱', this.description = '', this.connectionId = ''});

  AppInfo withConnection(String c) => AppInfo(id: id, name: name, icon: icon, description: description, connectionId: c);

  /// Unique across all connections.
  String get key => '$connectionId/$id';
}

enum UserStatus { active, restricted, suspended, banned }

/// Roles an admin can give a user. The app decides what each one unlocks.
const userRoles = {'user': 'مستخدم', 'vip': 'مميز VIP', 'moderator': 'مشرف محتوى'};

/// Subscription plans.
const userPlans = {'free': 'مجاني', 'pro': 'Pro', 'max': 'Max'};

/// Features an admin can switch off for one user. Apps check these keys.
const userFeatures = {
  'chat': 'المحادثة',
  'post': 'النشر والتعليق',
  'upload': 'رفع الصور والملفات',
  'generate': 'توليد الصور والفيديو',
  'purchase': 'الشراء والاشتراك',
  'profile_edit': 'تعديل الملف الشخصي',
};

/// Fields only admins may change. The Firestore rules enforce the same list.
const moderationFields = [
  'banned', 'banReason', 'suspendedUntil', 'role', 'plan', 'points', 'verified', 'restrictions',
  'warnings', 'lastWarning', 'adminMessage', 'adminMessageAt', 'forceLogoutAt',
];

/// One user account inside an app.
class AppUser {
  final String id;
  final String name;
  final String email;
  final String phone;
  final DateTime? createdAt;
  final DateTime? lastSeen;
  final String device;
  final String appVersion;
  final DateTime? lastLogin;
  final List<String> providers;
  final String photoUrl;

  final bool banned;
  final String banReason;
  final DateTime? suspendedUntil;
  final String role;
  final String plan;
  final int points;
  final bool verified;
  final List<String> restrictions;
  final int warnings;
  final String lastWarning;
  final String adminMessage;
  final DateTime? adminMessageAt;
  final DateTime? forceLogoutAt;

  /// Any other fields the app stores (shown read-only).
  final Map<String, String> extra;

  const AppUser({
    required this.id,
    this.name = '',
    this.email = '',
    this.phone = '',
    this.createdAt,
    this.lastSeen,
    this.device = '',
    this.appVersion = '',
    this.lastLogin,
    this.providers = const [],
    this.photoUrl = '',
    this.banned = false,
    this.banReason = '',
    this.suspendedUntil,
    this.role = 'user',
    this.plan = 'free',
    this.points = 0,
    this.verified = false,
    this.restrictions = const [],
    this.warnings = 0,
    this.lastWarning = '',
    this.adminMessage = '',
    this.adminMessageAt,
    this.forceLogoutAt,
    this.extra = const {},
  });

  String get displayName => name.trim().isEmpty ? (email.isEmpty ? 'بدون اسم' : email.split('@').first) : name.trim();

  UserStatus statusAt(DateTime now) {
    if (banned) return UserStatus.banned;
    if (suspendedUntil != null && suspendedUntil!.isAfter(now)) return UserStatus.suspended;
    if (restrictions.isNotEmpty) return UserStatus.restricted;
    return UserStatus.active;
  }

  UserStatus get status => statusAt(DateTime.now());

  bool get onlineRecently => lastSeen != null && DateTime.now().difference(lastSeen!).inMinutes < 15;

  /// Builds a user from plain field values (as stored in Firestore).
  factory AppUser.fromMap(String id, Map<String, Object?> f) {
    const known = {
      'name', 'email', 'phone', 'createdAt', 'lastSeen', 'device', 'appVersion', 'lastLogin', 'providers',
      'photoUrl', ...moderationFields,
    };
    DateTime? date(String k) => f[k] is DateTime ? f[k] as DateTime : null;
    String str(String k) => f[k] == null ? '' : '${f[k]}';
    return AppUser(
      id: id,
      name: str('name'),
      email: str('email'),
      phone: str('phone'),
      createdAt: date('createdAt'),
      lastSeen: date('lastSeen'),
      device: str('device'),
      appVersion: str('appVersion'),
      lastLogin: date('lastLogin'),
      providers: [for (final p in (f['providers'] as List?) ?? const []) '$p'],
      photoUrl: str('photoUrl'),
      banned: f['banned'] == true,
      banReason: str('banReason'),
      suspendedUntil: date('suspendedUntil'),
      role: str('role').isEmpty ? 'user' : str('role'),
      plan: str('plan').isEmpty ? 'free' : str('plan'),
      points: (f['points'] as num?)?.toInt() ?? 0,
      verified: f['verified'] == true,
      restrictions: [for (final r in (f['restrictions'] as List?) ?? const []) '$r'],
      warnings: (f['warnings'] as num?)?.toInt() ?? 0,
      lastWarning: str('lastWarning'),
      adminMessage: str('adminMessage'),
      adminMessageAt: date('adminMessageAt'),
      forceLogoutAt: date('forceLogoutAt'),
      extra: {
        for (final e in f.entries)
          if (!known.contains(e.key) && e.value != null && e.value is! Map && e.value is! List) e.key: '${e.value}',
      },
    );
  }

  Map<String, Object?> toMap() => {
        'name': name,
        'email': email,
        'phone': phone,
        'createdAt': createdAt,
        'lastSeen': lastSeen,
        'device': device,
        'appVersion': appVersion,
        'lastLogin': lastLogin,
        'providers': providers,
        'photoUrl': photoUrl,
        'banned': banned,
        'banReason': banReason,
        'suspendedUntil': suspendedUntil,
        'role': role,
        'plan': plan,
        'points': points,
        'verified': verified,
        'restrictions': restrictions,
        'warnings': warnings,
        'lastWarning': lastWarning,
        'adminMessage': adminMessage,
        'adminMessageAt': adminMessageAt,
        'forceLogoutAt': forceLogoutAt,
        ...extra,
      };

  AppUser apply(Map<String, Object?> changes) => AppUser.fromMap(id, {...toMap(), ...changes});
}

/// One admin action, kept so you can see who did what and when.
class LogEntry {
  final String id;
  final String appId;
  final String userId;
  final String userName;
  final String action;
  final String detail;
  final String by;
  final DateTime at;

  const LogEntry({
    this.id = '',
    required this.appId,
    required this.userId,
    required this.userName,
    required this.action,
    this.detail = '',
    this.by = '',
    required this.at,
  });
}

/// One stored record that belongs to a user, found in the app's database.
class DataDoc {
  final String path;
  final Map<String, Object?> fields;
  const DataDoc(this.path, this.fields);
}

/// Something the user did, as recorded by the app or by sign-in.
class ActivityEvent {
  final DateTime at;
  final String title;
  final String detail;
  final String icon;
  const ActivityEvent({required this.at, required this.title, this.detail = '', this.icon = '•'});
}

/// Everything known about one user, for the details page.
class UserInsights {
  /// Raw account facts (label → value).
  final Map<String, String> account;
  final List<DataDoc> data;
  final List<ActivityEvent> events;

  /// Why some part could not be loaded (empty when all is fine).
  final List<String> notes;

  const UserInsights({this.account = const {}, this.data = const [], this.events = const [], this.notes = const []});
}

/// Human labels for sign-in providers.
const providerNames = {
  'password': 'إيميل وكلمة مرور',
  'google.com': 'Google',
  'apple.com': 'Apple',
  'facebook.com': 'Facebook',
  'twitter.com': 'X (Twitter)',
  'github.com': 'GitHub',
  'phone': 'رقم الجوال',
  'anonymous': 'زائر',
};

/// What kind of content a stored record is, from its collection name.
(String label, String icon, bool social) contentKind(String path) {
  final parts = path.split('/');
  final col = (parts.length >= 2 ? parts[parts.length - 2] : path).toLowerCase();
  bool has(List<String> words) => words.any(col.contains);
  if (has(['stor'])) return ('قصة', '⏳', true);
  if (has(['moment', 'reel', 'short'])) return ('لحظة', '✨', true);
  if (has(['post', 'feed', 'tweet', 'status'])) return ('منشور', '📝', true);
  if (has(['comment', 'repl'])) return ('تعليق', '💬', true);
  if (has(['photo', 'image', 'media', 'gallery', 'video'])) return ('وسائط', '🖼️', true);
  if (has(['like', 'reaction', 'favorite', 'favourite'])) return ('إعجاب', '❤️', true);
  if (has(['follow', 'friend', 'connection'])) return ('متابعة', '👥', true);
  if (has(['message', 'chat', 'conversation'])) return ('رسالة', '✉️', true);
  if (has(['order', 'purchase', 'payment', 'transaction'])) return ('طلب', '🧾', false);
  if (has(['review', 'rating'])) return ('تقييم', '⭐', false);
  if (has(['notification'])) return ('إشعار', '🔔', false);
  if (has(['user', 'profile', 'account', 'member'])) return ('الملف الشخصي', '👤', false);
  return (col, '🗂️', false);
}

const _textKeys = ['text', 'content', 'caption', 'body', 'message', 'title', 'description', 'comment'];
const _mediaKeys = ['imageUrl', 'image', 'photoUrl', 'photo', 'mediaUrl', 'media', 'videoUrl', 'video', 'thumbnail', 'url', 'images', 'photos', 'mediaUrls'];

extension DataDocView on DataDoc {
  String get mainText {
    for (final k in _textKeys) {
      final v = fields[k];
      if (v is String && v.trim().isNotEmpty) return v.trim();
    }
    return '';
  }

  /// Picture and video links found in the record.
  List<String> get media {
    final out = <String>[];
    void add(Object? v) {
      if (v is String && v.startsWith('http')) out.add(v);
      if (v is List) v.forEach(add);
      if (v is Map) v.values.forEach(add);
    }
    for (final k in _mediaKeys) {
      add(fields[k]);
    }
    for (final v in fields.values) {
      if (v is String && RegExp(r'^https?://\S+\.(jpe?g|png|webp|gif|mp4|mov)(\?|$)', caseSensitive: false).hasMatch(v)) {
        if (!out.contains(v)) out.add(v);
      }
    }
    return out;
  }

  DateTime? get when {
    for (final k in const ['createdAt', 'timestamp', 'date', 'time', 'at', 'updatedAt', 'postedAt']) {
      final v = fields[k];
      if (v is DateTime) return v;
    }
    return null;
  }

  int? count(List<String> keys) {
    for (final k in keys) {
      final v = fields[k];
      if (v is num) return v.toInt();
      if (v is List) return v.length;
    }
    return null;
  }
}
