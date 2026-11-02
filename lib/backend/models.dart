/// An app you built, whose users this hub manages.
class AppInfo {
  final String id;
  final String name;
  final String icon;
  final String description;

  const AppInfo({required this.id, required this.name, this.icon = '📱', this.description = ''});
}

enum UserStatus { active, suspended, banned }

/// One user account inside an app.
class AppUser {
  final String id;
  final String name;
  final String email;
  final DateTime? createdAt;
  final DateTime? lastSeen;
  final bool banned;
  final DateTime? suspendedUntil;
  final String banReason;
  final Map<String, String> extra;

  const AppUser({
    required this.id,
    required this.name,
    required this.email,
    this.createdAt,
    this.lastSeen,
    this.banned = false,
    this.suspendedUntil,
    this.banReason = '',
    this.extra = const {},
  });

  UserStatus statusAt(DateTime now) {
    if (banned) return UserStatus.banned;
    if (suspendedUntil != null && suspendedUntil!.isAfter(now)) return UserStatus.suspended;
    return UserStatus.active;
  }

  UserStatus get status => statusAt(DateTime.now());

  AppUser copyWith({bool? banned, DateTime? suspendedUntil, bool clearSuspension = false, String? banReason}) => AppUser(
        id: id,
        name: name,
        email: email,
        createdAt: createdAt,
        lastSeen: lastSeen,
        banned: banned ?? this.banned,
        suspendedUntil: clearSuspension ? null : (suspendedUntil ?? this.suspendedUntil),
        banReason: banReason ?? this.banReason,
        extra: extra,
      );
}
