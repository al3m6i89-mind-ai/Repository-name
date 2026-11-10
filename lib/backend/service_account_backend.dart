import 'dart:convert';

import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:http/http.dart' as http;

import 'backend.dart';
import 'firebase_backend.dart' show decodeFields;
import 'local_store.dart';
import 'models.dart';

/// Full control of a Firebase project's sign-in accounts through a service
/// account key, with no change needed in the app itself:
///
/// * ban / suspension → the account is disabled, so sign-in is refused
/// * force sign-out   → all refresh tokens are revoked
/// * delete           → the account is removed from Firebase Authentication
/// * role, plan, points, restrictions, warnings, message → stored as the
///   user's custom claims, readable by the app from the ID token
class ServiceAccountBackend implements AdminBackend {
  static const appId = 'auth';

  final Map<String, dynamic> key;
  final LocalStore store;
  final http.Client _http;

  ServiceAccountBackend(this.key, this.store, {http.Client? client}) : _http = client ?? http.Client();

  /// Parses and checks the JSON file downloaded from Firebase.
  static Map<String, dynamic> parseKey(String text) {
    Map<String, dynamic> k;
    try {
      k = jsonDecode(text.trim()) as Map<String, dynamic>;
    } catch (_) {
      throw BackendError('الملف ليس JSON صحيح. اختر ملف المفتاح اللي نزّلته من Firebase كما هو.');
    }
    if (k['type'] != 'service_account' || k['private_key'] == null || k['client_email'] == null || k['project_id'] == null) {
      throw BackendError('هذا ليس ملف حساب خدمة. نزّله من: إعدادات المشروع ← Service accounts ← Generate new private key.');
    }
    return k;
  }

  String get projectId => '${key['project_id']}';

  @override
  String get label => 'Firebase · $projectId';

  @override
  bool get isDemo => false;

  @override
  String? get adminEmail => '${key['client_email']}';

  @override
  Map<String, String> get sessionData => const {};

  String? _access;
  DateTime _expires = DateTime.fromMillisecondsSinceEpoch(0);

  Future<String> _token() async {
    if (_access != null && DateTime.now().isBefore(_expires)) return _access!;
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final String assertion;
    try {
      assertion = JWT(
        {
          'iss': key['client_email'],
          'scope': 'https://www.googleapis.com/auth/cloud-platform https://www.googleapis.com/auth/identitytoolkit '
              'https://www.googleapis.com/auth/datastore https://www.googleapis.com/auth/firebase '
              'https://www.googleapis.com/auth/firebase.messaging',
          'aud': 'https://oauth2.googleapis.com/token',
          'iat': now,
          'exp': now + 3600,
        },
        header: {'kid': key['private_key_id']},
      ).sign(RSAPrivateKey('${key['private_key']}'), algorithm: JWTAlgorithm.RS256);
    } catch (e) {
      throw BackendError('المفتاح الخاص في الملف تالف: $e');
    }
    final res = await _http.post(
      Uri.parse('https://oauth2.googleapis.com/token'),
      body: {'grant_type': 'urn:ietf:params:oauth:grant-type:jwt-bearer', 'assertion': assertion},
    );
    final body = _json(res);
    if (res.statusCode != 200) {
      throw BackendError('رفض Google المفتاح (${body['error_description'] ?? body['error'] ?? res.statusCode}). '
          'ربما حُذف المفتاح، أنشئ مفتاحاً جديداً.');
    }
    _access = body['access_token'];
    _expires = DateTime.now().add(Duration(seconds: (body['expires_in'] as num? ?? 3600).toInt() - 120));
    return _access!;
  }

  String get _auth => 'https://identitytoolkit.googleapis.com/v1/projects/$projectId';
  String get _docs => 'https://firestore.googleapis.com/v1/projects/$projectId/databases/(default)/documents';

  Future<Map<String, dynamic>> _call(String method, String url, {Object? body, bool soft = false}) async {
    final req = http.Request(method, Uri.parse(url))
      ..headers['Authorization'] = 'Bearer ${await _token()}'
      ..headers['Content-Type'] = 'application/json';
    if (body != null) req.body = jsonEncode(body);
    final res = await http.Response.fromStream(await _http.send(req));
    final json = _json(res);
    if (res.statusCode >= 300) {
      final msg = (json['error'] as Map?)?['message'] ?? res.body;
      if (soft) throw _Soft(res.statusCode, '$msg');
      if (res.statusCode == 403) {
        throw BackendError('حساب الخدمة ما عنده صلاحية ($msg). تأكد إنه من نفس المشروع وإن Authentication مفعّل.');
      }
      throw BackendError('خطأ من Firebase (${res.statusCode}): $msg');
    }
    return json;
  }

  @override
  Future<void> connect() async {
    await _token();
    await _call('GET', '$_auth/accounts:batchGet?maxResults=1');
  }

  // Apps -----------------------------------------------------------------------

  @override
  Future<List<AppInfo>> listApps() async => [AppInfo(id: appId, name: projectId, icon: '🔥', description: 'Firebase Authentication')];

  @override
  Future<void> saveApp(AppInfo app) async {}

  @override
  Future<void> deleteApp(String appId) async {}

  // Users ----------------------------------------------------------------------

  @override
  Future<List<AppUser>> listUsers(String appId) async {
    final out = <AppUser>[];
    String? page;
    do {
      final body = await _call('GET', '$_auth/accounts:batchGet?maxResults=1000${page == null ? '' : '&nextPageToken=$page'}');
      for (final u in (body['users'] as List?) ?? const []) {
        out.add(await _liftExpired(_toUser(u as Map<String, dynamic>)));
      }
      page = body['nextPageToken'];
      if (page != null && page.isEmpty) page = null;
    } while (page != null);
    return out;
  }

  @override
  Future<AppUser?> getUser(String appId, String userId) async {
    final raw = await _raw(userId);
    return raw == null ? null : _toUser(raw);
  }

  Future<Map<String, dynamic>?> _raw(String uid) async {
    final body = await _call('POST', '$_auth/accounts:lookup', body: {'localId': [uid]});
    final users = body['users'] as List?;
    return users == null || users.isEmpty ? null : users.first as Map<String, dynamic>;
  }

  /// A suspension that has run out re-enables the account the next time
  /// the hub lists users.
  Future<AppUser> _liftExpired(AppUser u) async {
    if (!u.banned && u.suspendedUntil != null && u.suspendedUntil!.isBefore(DateTime.now()) && _disabled.contains(u.id)) {
      try {
        await updateUser(appId, u.id, {'suspendedUntil': null});
        return u.apply({'suspendedUntil': null});
      } catch (_) {}
    }
    return u;
  }

  final Set<String> _disabled = {};

  AppUser _toUser(Map<String, dynamic> u) {
    final claims = _claims(u);
    DateTime? ms(Object? v) => v == null ? null : DateTime.fromMillisecondsSinceEpoch(int.tryParse('$v') ?? 0);
    DateTime? iso(Object? v) => v is String ? DateTime.tryParse(v)?.toLocal() : null;
    final disabled = u['disabled'] == true;
    if (disabled) _disabled.add('${u['localId']}');
    final suspended = iso(claims['suspendedUntil']);
    final lastRefresh = iso(u['lastRefreshAt']);
    final lastLogin = ms(u['lastLoginAt']);
    return AppUser(
      id: '${u['localId']}',
      name: '${u['displayName'] ?? ''}',
      email: '${u['email'] ?? ''}',
      phone: '${u['phoneNumber'] ?? ''}',
      photoUrl: '${u['photoUrl'] ?? ''}',
      createdAt: ms(u['createdAt']),
      lastLogin: lastLogin,
      lastSeen: [lastRefresh, lastLogin].whereType<DateTime>().fold<DateTime?>(null, (a, b) => a == null || b.isAfter(a) ? b : a),
      providers: [
        for (final p in (u['providerUserInfo'] as List?) ?? const []) '${(p as Map)['providerId']}',
        if (((u['providerUserInfo'] as List?) ?? const []).isEmpty) 'anonymous',
      ],
      verified: u['emailVerified'] == true,
      // Disabled without a suspension date counts as a ban (also for accounts
      // disabled from the Firebase console).
      banned: claims['banned'] == true || (disabled && suspended == null),
      banReason: '${claims['banReason'] ?? ''}',
      suspendedUntil: suspended,
      role: '${claims['role'] ?? 'user'}',
      plan: '${claims['plan'] ?? 'free'}',
      points: (claims['points'] as num?)?.toInt() ?? 0,
      restrictions: [for (final r in (claims['restrictions'] as List?) ?? const []) '$r'],
      warnings: (claims['warnings'] as num?)?.toInt() ?? 0,
      lastWarning: '${claims['lastWarning'] ?? ''}',
      adminMessage: '${claims['adminMessage'] ?? ''}',
      adminMessageAt: iso(claims['adminMessageAt']),
      forceLogoutAt: u['validSince'] == null ? null : DateTime.fromMillisecondsSinceEpoch(int.parse('${u['validSince']}') * 1000),
      extra: {
        for (final e in claims.entries)
          if (!moderationFields.contains(e.key) && e.value is! Map && e.value is! List) 'claim:${e.key}': '${e.value}',
      },
    );
  }

  static Map<String, dynamic> _claims(Map<String, dynamic> u) {
    try {
      return (jsonDecode('${u['customAttributes'] ?? '{}'}') as Map).cast<String, dynamic>();
    } catch (_) {
      return {};
    }
  }

  @override
  Future<void> updateUser(String appId, String userId, Map<String, Object?> changes) async {
    final raw = await _raw(userId);
    if (raw == null) throw BackendError('المستخدم غير موجود');
    final claims = _claims(raw);
    final body = <String, Object?>{'localId': userId};

    for (final e in changes.entries) {
      final v = e.value;
      switch (e.key) {
        case 'name':
          body['displayName'] = v;
        case 'email':
          if ('$v'.isNotEmpty) body['email'] = v;
        case 'phone':
          if ('$v'.isNotEmpty) body['phoneNumber'] = v;
        case 'verified':
          body['emailVerified'] = v == true;
        case 'forceLogoutAt':
          body['validSince'] = '${(v as DateTime? ?? DateTime.now()).millisecondsSinceEpoch ~/ 1000}';
        default:
          if (v == null || v == '' || (v is List && v.isEmpty) || v == false || (e.key == 'warnings' && v == 0)) {
            claims.remove(e.key);
          } else if (v is DateTime) {
            claims[e.key] = v.toUtc().toIso8601String();
          } else if (e.key == 'adminMessage' || e.key == 'lastWarning' || e.key == 'banReason') {
            final s = '$v';
            claims[e.key] = s.length > 200 ? s.substring(0, 200) : s;
          } else {
            claims[e.key] = v;
          }
      }
    }

    final banned = claims['banned'] == true;
    final until = DateTime.tryParse('${claims['suspendedUntil'] ?? ''}');
    final suspended = until != null && until.isAfter(DateTime.now());
    if (changes.containsKey('banned') || changes.containsKey('suspendedUntil')) {
      body['disableUser'] = banned || suspended;
      if (!banned && !suspended) claims.remove('suspendedUntil');
      if (banned || suspended) _disabled.add(userId);
    }
    final encoded = jsonEncode(claims);
    if (encoded.length > 1000) throw BackendError('بيانات المستخدم الإضافية كبيرة. قصّر الرسالة أو السبب.');
    body['customAttributes'] = encoded;
    await _call('POST', '$_auth/accounts:update', body: body);
    // A ban or suspension also signs the user out everywhere right away.
    if (body['disableUser'] == true) {
      await _call('POST', '$_auth/accounts:update', body: {
        'localId': userId,
        'validSince': '${DateTime.now().millisecondsSinceEpoch ~/ 1000}',
      });
    }
  }

  @override
  Future<void> deleteUser(String appId, String userId) async {
    await _call('POST', '$_auth/accounts:delete', body: {'localId': userId});
  }

  // Details --------------------------------------------------------------------

  static const _ownerFields = ['uid', 'userId', 'userID', 'user_id', 'ownerId', 'owner', 'createdBy', 'authorId', 'author'];

  @override
  Future<UserInsights> getInsights(String appId, AppUser u) async {
    final raw = await _raw(u.id) ?? {};
    final notes = <String>[];
    final account = <String, String>{
      'المعرّف (UID)': u.id,
      'طرق الدخول': u.providers.map((p) => providerNames[p] ?? p).join('، '),
      'الإيميل موثّق': raw['emailVerified'] == true ? 'نعم' : 'لا',
      'الحساب معطّل': raw['disabled'] == true ? 'نعم' : 'لا',
      if (raw['passwordUpdatedAt'] != null)
        'آخر تغيير لكلمة المرور': '${DateTime.fromMillisecondsSinceEpoch((raw['passwordUpdatedAt'] as num).toInt())}',
      if (raw['lastRefreshAt'] != null) 'آخر نشاط (تجديد الجلسة)': '${DateTime.tryParse('${raw['lastRefreshAt']}')?.toLocal()}',
      if (raw['tenantId'] != null) 'Tenant': '${raw['tenantId']}',
      if (raw['customAttributes'] != null) 'Custom claims': '${raw['customAttributes']}',
    };
    for (final p in (raw['providerUserInfo'] as List?) ?? const []) {
      final m = p as Map;
      account['حساب ${providerNames[m['providerId']] ?? m['providerId']}'] =
          [m['email'], m['displayName'], m['phoneNumber'], m['rawId']].where((x) => x != null).join(' · ');
    }
    for (final f in (raw['mfaInfo'] as List?) ?? const []) {
      account['تحقق بخطوتين'] = '${(f as Map)['displayName'] ?? f['phoneInfo'] ?? 'مفعّل'}';
    }

    final events = <ActivityEvent>[
      if (u.createdAt != null) ActivityEvent(at: u.createdAt!, title: 'أنشأ الحساب', detail: account['طرق الدخول'] ?? '', icon: '🎉'),
      if (u.lastLogin != null) ActivityEvent(at: u.lastLogin!, title: 'آخر تسجيل دخول', icon: '🔐'),
      if (raw['lastRefreshAt'] != null)
        ActivityEvent(at: DateTime.tryParse('${raw['lastRefreshAt']}')!.toLocal(), title: 'آخر استخدام للتطبيق', icon: '📱'),
      if (raw['passwordUpdatedAt'] != null)
        ActivityEvent(
            at: DateTime.fromMillisecondsSinceEpoch((raw['passwordUpdatedAt'] as num).toInt()), title: 'غيّر كلمة المرور', icon: '🔑'),
    ];

    final data = <DataDoc>[];
    try {
      data.addAll(await _findUserData(u));
      for (final d in data) {
        for (final k in const ['createdAt', 'updatedAt', 'timestamp', 'date', 'time', 'at']) {
          final v = d.fields[k];
          if (v is DateTime) {
            events.add(ActivityEvent(at: v, title: _verb(d.path, k), detail: d.path, icon: '🗂️'));
            break;
          }
        }
      }
    } on _Soft catch (e) {
      notes.add(e.code == 404 || e.message.contains('does not exist')
          ? 'ما فيه قاعدة بيانات Firestore في هذا المشروع.'
          : 'تعذّر قراءة قاعدة البيانات: ${e.message}');
    } catch (e) {
      notes.add('تعذّر قراءة قاعدة البيانات: $e');
    }
    events.sort((a, b) => b.at.compareTo(a.at));
    return UserInsights(account: account, data: data, events: events, notes: notes);
  }

  static String _verb(String path, String field) {
    final col = path.split('/').reversed.skip(1).first;
    return field == 'updatedAt' ? 'حدّث $col' : 'أنشأ $col';
  }

  /// Looks through Firestore for records of this user: a document named by
  /// their UID in any top-level collection (and its sub-collections), and
  /// documents whose owner field holds their UID.
  Future<List<DataDoc>> _findUserData(AppUser u) async {
    final found = <String, DataDoc>{};
    final cols = await _collectionIds(_docs);
    for (final col in cols.take(25)) {
      final direct = await _getDoc('$_docs/$col/${u.id}');
      if (direct != null) {
        found[direct.path] = direct;
        for (final sub in (await _collectionIds('$_docs/$col/${u.id}')).take(10)) {
          for (final d in await _listDocs('$_docs/$col/${u.id}/$sub', 50)) {
            found[d.path] = d;
          }
        }
      }
      for (final d in await _ownedBy(col, u)) {
        found.putIfAbsent(d.path, () => d);
      }
      if (found.length > 150) break;
    }
    return found.values.toList();
  }

  Future<List<String>> _collectionIds(String parent) async {
    final body = await _call('POST', '$parent:listCollectionIds', body: {'pageSize': 100}, soft: true);
    return [for (final c in (body['collectionIds'] as List?) ?? const []) '$c'];
  }

  Future<DataDoc?> _getDoc(String url) async {
    try {
      final d = await _call('GET', url, soft: true);
      return DataDoc(_path(d), decodeFields(d['fields']));
    } on _Soft catch (e) {
      if (e.code == 404) return null;
      rethrow;
    }
  }

  Future<List<DataDoc>> _listDocs(String url, int limit) async {
    final body = await _call('GET', '$url?pageSize=$limit', soft: true);
    return [
      for (final d in (body['documents'] as List?) ?? const [])
        DataDoc(_path(d as Map<String, dynamic>), decodeFields(d['fields'])),
    ];
  }

  Future<List<DataDoc>> _ownedBy(String col, AppUser u) async {
    final filters = [
      for (final f in _ownerFields)
        {'fieldFilter': {'field': {'fieldPath': f}, 'op': 'EQUAL', 'value': {'stringValue': u.id}}},
      if (u.email.isNotEmpty)
        {'fieldFilter': {'field': {'fieldPath': 'email'}, 'op': 'EQUAL', 'value': {'stringValue': u.email}}},
    ];
    try {
      final req = http.Request('POST', Uri.parse('$_docs:runQuery'))
        ..headers['Authorization'] = 'Bearer ${await _token()}'
        ..headers['Content-Type'] = 'application/json'
        ..body = jsonEncode({
          'structuredQuery': {
            'from': [{'collectionId': col}],
            'where': {'compositeFilter': {'op': 'OR', 'filters': filters}},
            'limit': 50,
          },
        });
      final res = await http.Response.fromStream(await _http.send(req));
      if (res.statusCode >= 300) return const [];
      return [
        for (final r in jsonDecode(utf8.decode(res.bodyBytes)) as List)
          if ((r as Map)['document'] != null)
            DataDoc(_path(r['document'] as Map<String, dynamic>), decodeFields((r['document'] as Map)['fields'])),
      ];
    } catch (_) {
      return const [];
    }
  }

  static String _path(Map<String, dynamic> d) => '${d['name']}'.split('/documents/').last;

  /// Finds FCM tokens the app saved for this user (any field whose name
  /// mentions "token", in their records or a tokens sub-collection) and
  /// sends each device a notification.
  @override
  Future<PushResult> sendPush(String appId, AppUser user, String title, String body) async {
    final tokens = <String>{};
    void collect(Object? key, Object? v) {
      final k = '$key'.toLowerCase();
      if (v is String && v.length > 100 && !v.contains(' ') && (k.contains('token') || k.contains('fcm') || k.isEmpty)) {
        tokens.add(v);
      } else if (v is List && (k.contains('token') || k.contains('fcm'))) {
        for (final x in v) {
          collect('', x);
        }
      } else if (v is Map && (k.contains('token') || k.contains('fcm') || k.contains('device'))) {
        v.forEach((kk, vv) => collect(k.contains('token') || k.contains('fcm') ? '' : kk, vv));
      }
    }

    try {
      for (final d in await _findUserData(user)) {
        final tokenDoc = d.path.toLowerCase().contains('token');
        d.fields.forEach((k, v) => collect(tokenDoc ? '' : k, v));
        // A tokens collection often uses the token itself as the document id.
        final id = d.path.split('/').last;
        if (tokenDoc && id.length > 100) tokens.add(id);
      }
    } catch (_) {}
    if (tokens.isEmpty) {
      return const PushResult(0, 0, 'ما لقيت رمز إشعارات (FCM token) لهذا المستخدم في قاعدة البيانات');
    }
    var sent = 0;
    String? lastError;
    for (final t in tokens) {
      try {
        await _call('POST', 'https://fcm.googleapis.com/v1/projects/$projectId/messages:send', body: {
          'message': {
            'token': t,
            'notification': {'title': title, 'body': body},
            'android': {'priority': 'high', 'notification': {'sound': 'default'}},
            'apns': {'payload': {'aps': {'sound': 'default'}}},
            'data': {'type': 'admin_message', 'body': body},
          },
        });
        sent++;
      } catch (e) {
        lastError = '$e';
      }
    }
    return PushResult(sent, tokens.length, sent == 0 ? (lastError ?? '') : '');
  }

  @override
  Future<void> deleteData(String path) async {
    await _call('DELETE', '$_docs/$path');
  }

  // Notes and logs live on this device ----------------------------------------

  @override
  Future<String> getNote(String appId, String userId) => store.getNote(userId);

  @override
  Future<void> setNote(String appId, String userId, String note) => store.setNote(userId, note);

  @override
  Future<void> addLog(LogEntry entry) => store.addLog(entry);

  @override
  Future<List<LogEntry>> listLogs({int limit = 200}) => store.listLogs(limit: limit);

  static Map<String, dynamic> _json(http.Response res) {
    try {
      final v = jsonDecode(utf8.decode(res.bodyBytes));
      return v is Map<String, dynamic> ? v : {};
    } catch (_) {
      return {};
    }
  }
}

class _Soft implements Exception {
  final int code;
  final String message;
  _Soft(this.code, this.message);
  @override
  String toString() => message;
}
