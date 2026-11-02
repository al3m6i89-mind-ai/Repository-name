import 'models.dart';

/// Where apps and users live. The UI only talks to this, so a new backend
/// (Supabase, your own server…) is one more class.
abstract class AdminBackend {
  String get label;

  /// Signs the admin in. Throws [BackendError] with an Arabic message on failure.
  Future<void> signIn(String email, String password);
  Future<void> signOut();
  String? get adminEmail;

  Future<List<AppInfo>> listApps();
  Future<void> saveApp(AppInfo app);
  Future<void> deleteApp(String appId);

  Future<List<AppUser>> listUsers(String appId);

  /// Permanently removes the user's record. The app then treats them as deleted.
  Future<void> deleteUser(String appId, String userId);
  Future<void> setBanned(String appId, String userId, bool banned, {String reason = ''});

  /// `until == null` lifts the suspension.
  Future<void> setSuspendedUntil(String appId, String userId, DateTime? until, {String reason = ''});
}

class BackendError implements Exception {
  final String message;
  BackendError(this.message);
  @override
  String toString() => message;
}
