import 'models.dart';

/// Where apps and users live. The UI only talks to this, so a new backend
/// (Supabase, your own server…) is one more class.
abstract class AdminBackend {
  String get label;
  bool get isDemo;

  /// Checks the connection works (signs in, or restores a saved session).
  /// Throws [BackendError] with an Arabic message on failure.
  Future<void> connect();
  String? get adminEmail;

  /// What to save so the next launch can reconnect without a password.
  Map<String, String> get sessionData => const {};

  Future<List<AppInfo>> listApps();
  Future<void> saveApp(AppInfo app);
  Future<void> deleteApp(String appId);

  Future<List<AppUser>> listUsers(String appId);
  Future<AppUser?> getUser(String appId, String userId);

  /// Changes some fields of a user (only those in [changes]).
  Future<void> updateUser(String appId, String userId, Map<String, Object?> changes);

  /// Permanently removes the user's record. The app then treats them as deleted.
  Future<void> deleteUser(String appId, String userId);

  /// Private admin note about a user (never visible to the user).
  Future<String> getNote(String appId, String userId);
  Future<void> setNote(String appId, String userId, String note);

  /// All details, stored data and activity of one user.
  Future<UserInsights> getInsights(String appId, AppUser user);

  /// Deletes one stored record of a user (a post, story, comment…).
  Future<void> deleteData(String path);

  /// Sends a phone notification to the user's devices, when the app saved
  /// their push token. Returns how many devices got it.
  Future<PushResult> sendPush(String appId, AppUser user, String title, String body);

  Future<void> addLog(LogEntry entry);

  /// Newest first.
  Future<List<LogEntry>> listLogs({int limit = 200});
}

class BackendError implements Exception {
  final String message;
  BackendError(this.message);
  @override
  String toString() => message;
}

class PushResult {
  final int sent;
  final int tokens;
  final String note;
  const PushResult(this.sent, this.tokens, [this.note = '']);
}
