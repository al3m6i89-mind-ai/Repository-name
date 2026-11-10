import 'backend.dart';
import 'models.dart';

/// Every admin action on a user goes through here so it is also logged.
class UserActions {
  final AdminBackend backend;
  UserActions(this.backend);

  Future<void> apply(String appId, AppUser user, String action, Map<String, Object?> changes,
      {String detail = ''}) async {
    await backend.updateUser(appId, user.id, changes);
    await _log(appId, user, action, detail);
  }

  Future<void> delete(String appId, AppUser user) async {
    await backend.deleteUser(appId, user.id);
    await _log(appId, user, 'حذف الحساب', user.email);
  }

  Future<void> _log(String appId, AppUser user, String action, String detail) async {
    try {
      await backend.addLog(LogEntry(
        appId: appId,
        userId: user.id,
        userName: user.displayName,
        action: action,
        detail: detail,
        by: backend.adminEmail ?? '',
        at: DateTime.now(),
      ));
    } catch (_) {
      // The action itself succeeded; a missing log line must not undo it.
    }
  }

  // Ready-made actions -------------------------------------------------------

  Future<void> ban(String appId, AppUser u, String reason) =>
      apply(appId, u, 'حظر دائم', {'banned': true, 'banReason': reason}, detail: reason);

  Future<void> unban(String appId, AppUser u) =>
      apply(appId, u, 'فك الحظر', {'banned': false, 'banReason': ''});

  Future<void> suspend(String appId, AppUser u, DateTime until, String reason) =>
      apply(appId, u, 'حجب مؤقت', {'suspendedUntil': until, 'banReason': reason},
          detail: 'حتى ${fmtDateTime(until)}${reason.isEmpty ? '' : ' · $reason'}');

  Future<void> unsuspend(String appId, AppUser u) =>
      apply(appId, u, 'رفع الحجب', {'suspendedUntil': null, 'banReason': ''});

  Future<void> warn(String appId, AppUser u, String text) =>
      apply(appId, u, 'تحذير', {'warnings': u.warnings + 1, 'lastWarning': text, 'adminMessage': '⚠️ $text', 'adminMessageAt': DateTime.now()},
          detail: text);

  Future<void> clearWarnings(String appId, AppUser u) =>
      apply(appId, u, 'مسح التحذيرات', {'warnings': 0, 'lastWarning': ''});

  Future<void> message(String appId, AppUser u, String text) =>
      apply(appId, u, 'رسالة للمستخدم', {'adminMessage': text, 'adminMessageAt': DateTime.now()}, detail: text);

  Future<void> forceLogout(String appId, AppUser u) =>
      apply(appId, u, 'تسجيل خروج إجباري', {'forceLogoutAt': DateTime.now()});

  Future<void> setRole(String appId, AppUser u, String role) =>
      apply(appId, u, 'تغيير الدور', {'role': role}, detail: '${userRoles[u.role] ?? u.role} ← ${userRoles[role] ?? role}');

  Future<void> setPlan(String appId, AppUser u, String plan) =>
      apply(appId, u, 'تغيير الخطة', {'plan': plan}, detail: '${userPlans[u.plan] ?? u.plan} ← ${userPlans[plan] ?? plan}');

  Future<void> addPoints(String appId, AppUser u, int delta) {
    final next = (u.points + delta).clamp(0, 1 << 31);
    return apply(appId, u, delta >= 0 ? 'إضافة نقاط' : 'خصم نقاط', {'points': next}, detail: '${delta >= 0 ? '+' : ''}$delta ← $next');
  }

  Future<void> setVerified(String appId, AppUser u, bool v) =>
      apply(appId, u, v ? 'توثيق الحساب' : 'إلغاء التوثيق', {'verified': v});

  Future<void> setRestrictions(String appId, AppUser u, List<String> r) => apply(
      appId, u, 'تقييد الميزات', {'restrictions': r},
      detail: r.isEmpty ? 'بدون قيود' : r.map((k) => userFeatures[k] ?? k).join('، '));

  Future<void> editProfile(String appId, AppUser u, {required String name, required String email, required String phone}) =>
      apply(appId, u, 'تعديل البيانات', {'name': name, 'email': email, 'phone': phone});
}

String _two(int n) => n.toString().padLeft(2, '0');

String fmtDate(DateTime? d) => d == null ? '—' : '${d.year}/${_two(d.month)}/${_two(d.day)}';

String fmtDateTime(DateTime? d) => d == null ? '—' : '${fmtDate(d)}  ${_two(d.hour)}:${_two(d.minute)}';

/// "منذ 5 دقائق" style.
String fmtAgo(DateTime? d) {
  if (d == null) return '—';
  final diff = DateTime.now().difference(d);
  if (diff.isNegative) return fmtDateTime(d);
  if (diff.inMinutes < 1) return 'الآن';
  if (diff.inMinutes < 60) return 'منذ ${diff.inMinutes} د';
  if (diff.inHours < 24) return 'منذ ${diff.inHours} س';
  if (diff.inDays < 30) return 'منذ ${diff.inDays} يوم';
  return fmtDate(d);
}

String fmtLeft(DateTime until) {
  final left = until.difference(DateTime.now());
  if (left.inDays >= 1) return '${left.inDays} يوم';
  if (left.inHours >= 1) return '${left.inHours} ساعة';
  return '${left.inMinutes.clamp(1, 59)} دقيقة';
}
