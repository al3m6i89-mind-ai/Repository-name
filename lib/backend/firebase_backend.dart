import 'dart:convert';

import 'package:http/http.dart' as http;

import 'backend.dart';
import 'models.dart';

/// Firebase over its REST APIs: no google-services.json and no native plugin,
/// just the project's Web API key and project ID.
///
/// Data layout in Firestore:
///   admins/{uid}                  – exists for each admin account
///   apps/{appId}                  – name, icon, description
///   apps/{appId}/users/{userId}   – the user's record (see [AppUser])
///   notes/{appId}__{userId}       – private admin note
///   logs/{auto}                   – one document per admin action
class FirebaseBackend implements AdminBackend {
  final String apiKey;
  final String projectId;
  final http.Client _http;
  final String? _loginEmail;
  String? _loginPassword;

  FirebaseBackend({
    required this.apiKey,
    required this.projectId,
    String? email,
    String? password,
    String? refreshToken,
    http.Client? client,
  })  : _http = client ?? http.Client(),
        _loginEmail = email,
        _loginPassword = password,
        _refreshToken = refreshToken,
        _email = email;

  String? _idToken;
  String? _refreshToken;
  String? _uid;
  String? _email;
  DateTime _expires = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  String get label => 'Firebase · $projectId';

  @override
  bool get isDemo => false;

  @override
  String? get adminEmail => _email;

  String get _docs => 'https://firestore.googleapis.com/v1/projects/$projectId/databases/(default)/documents';

  @override
  Map<String, String> get sessionData => {'refreshToken': _refreshToken ?? '', 'email': _email ?? ''};

  @override
  Future<void> connect() async {
    final password = _loginPassword;
    if (password != null && password.isNotEmpty) {
      _loginPassword = null;
      return signIn(_loginEmail ?? '', password);
    }
    if (_refreshToken == null || _refreshToken!.isEmpty) throw BackendError('سجّل الدخول بالإيميل وكلمة المرور');
    _idToken = '';
    _expires = DateTime.fromMillisecondsSinceEpoch(0);
    await _token();
    _uid = _uidFromToken(_idToken!);
    final admin = await _send('GET', '$_docs/admins/$_uid', allow404: true);
    if (admin == null) throw BackendError('هذا الحساب ليس مشرفاً في $projectId');
  }

  static String? _uidFromToken(String jwt) {
    try {
      final part = jwt.split('.')[1];
      final json = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(part))));
      return json['user_id'] ?? json['sub'];
    } catch (_) {
      return null;
    }
  }

  Future<void> signIn(String email, String password) async {
    final res = await _http.post(
      Uri.parse('https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=$apiKey'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email.trim(), 'password': password, 'returnSecureToken': true}),
    );
    final body = _json(res);
    if (res.statusCode != 200) throw BackendError(_authError(body));
    _idToken = body['idToken'];
    _refreshToken = body['refreshToken'];
    _uid = body['localId'];
    _email = body['email'];
    _expires = DateTime.now().add(Duration(seconds: int.parse('${body['expiresIn'] ?? 3600}') - 60));

    final admin = await _send('GET', '$_docs/admins/$_uid', allow404: true);
    if (admin == null) {
      final uid = _uid;
      _idToken = _refreshToken = null;
      throw BackendError('هذا الحساب ليس مشرفاً. أضف مستند admins/$uid في Firestore (راجع دليل الإعداد).');
    }
  }

  Future<String> _token() async {
    if (_idToken == null) throw BackendError('سجّل الدخول أولاً');
    if (DateTime.now().isAfter(_expires)) {
      final res = await _http.post(
        Uri.parse('https://securetoken.googleapis.com/v1/token?key=$apiKey'),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {'grant_type': 'refresh_token', 'refresh_token': _refreshToken ?? ''},
      );
      final body = _json(res);
      if (res.statusCode != 200) throw BackendError('انتهت الجلسة، سجّل الدخول مرة ثانية');
      _idToken = body['id_token'];
      _refreshToken = body['refresh_token'];
      _expires = DateTime.now().add(Duration(seconds: int.parse('${body['expires_in'] ?? 3600}') - 60));
    }
    return _idToken!;
  }

  Future<Map<String, dynamic>?> _send(String method, String url, {Object? body, bool allow404 = false}) async {
    final req = http.Request(method, Uri.parse(url))
      ..headers['Authorization'] = 'Bearer ${await _token()}'
      ..headers['Content-Type'] = 'application/json';
    if (body != null) req.body = jsonEncode(body);
    final res = await http.Response.fromStream(await _http.send(req));
    if (allow404 && res.statusCode == 404) return null;
    if (res.statusCode == 403) throw BackendError('ما عندك صلاحية. تأكد من قواعد Firestore ومن مستند admins.');
    if (res.statusCode >= 300) {
      final msg = (_json(res)['error'] as Map?)?['message'] ?? res.body;
      throw BackendError('خطأ من Firebase (${res.statusCode}): $msg');
    }
    return _json(res);
  }

  Future<List<Map<String, dynamic>>> _list(String url) async {
    final out = <Map<String, dynamic>>[];
    String? page;
    do {
      final body = await _send('GET', '$url?pageSize=300${page == null ? '' : '&pageToken=$page'}');
      out.addAll(((body?['documents'] as List?) ?? const []).cast<Map<String, dynamic>>());
      page = body?['nextPageToken'];
    } while (page != null);
    return out;
  }

  @override
  Future<List<AppInfo>> listApps() async {
    final docs = await _list('$_docs/apps');
    return [
      for (final d in docs)
        () {
          final f = decodeFields(d['fields']);
          return AppInfo(
            id: _id(d),
            name: '${f['name'] ?? _id(d)}',
            icon: '${f['icon'] ?? '📱'}',
            description: '${f['description'] ?? ''}',
          );
        }(),
    ];
  }

  @override
  Future<void> saveApp(AppInfo app) => _patch('$_docs/apps/${app.id}', {
        'name': app.name,
        'icon': app.icon,
        'description': app.description,
      });

  @override
  Future<void> deleteApp(String appId) async => _send('DELETE', '$_docs/apps/$appId');

  @override
  Future<List<AppUser>> listUsers(String appId) async {
    final docs = await _list('$_docs/apps/$appId/users');
    return docs.map((d) => AppUser.fromMap(_id(d), decodeFields(d['fields']))).toList();
  }

  @override
  Future<AppUser?> getUser(String appId, String userId) async {
    final d = await _send('GET', '$_docs/apps/$appId/users/$userId', allow404: true);
    return d == null ? null : AppUser.fromMap(userId, decodeFields(d['fields']));
  }

  @override
  Future<void> updateUser(String appId, String userId, Map<String, Object?> changes) =>
      _patch('$_docs/apps/$appId/users/$userId', changes, mustExist: true);

  @override
  Future<void> deleteUser(String appId, String userId) async {
    await _send('DELETE', '$_docs/apps/$appId/users/$userId');
    await _send('DELETE', '$_docs/notes/${appId}__$userId');
  }

  @override
  Future<String> getNote(String appId, String userId) async {
    final d = await _send('GET', '$_docs/notes/${appId}__$userId', allow404: true);
    return '${decodeFields(d?['fields'])['text'] ?? ''}';
  }

  @override
  Future<void> setNote(String appId, String userId, String note) =>
      _patch('$_docs/notes/${appId}__$userId', {'text': note, 'updatedAt': DateTime.now()});

  @override
  Future<UserInsights> getInsights(String appId, AppUser u) async {
    final notes = <String>[];
    final events = <ActivityEvent>[];
    try {
      final docs = await _list('$_docs/apps/$appId/users/${u.id}/events');
      for (final d in docs) {
        final f = decodeFields(d['fields']);
        events.add(ActivityEvent(
          at: f['at'] is DateTime ? f['at'] as DateTime : DateTime.fromMillisecondsSinceEpoch(0),
          title: '${f['type'] ?? 'حدث'}',
          detail: '${f['detail'] ?? ''}',
          icon: '${f['icon'] ?? '•'}',
        ));
      }
    } catch (e) {
      notes.add('سجل النشاط: $e');
    }
    if (u.createdAt != null) events.add(ActivityEvent(at: u.createdAt!, title: 'أنشأ الحساب', icon: '🎉'));
    events.sort((a, b) => b.at.compareTo(a.at));
    return UserInsights(
      account: {
        'المعرّف (UID)': u.id,
        if (u.device.isNotEmpty) 'الجهاز': u.device,
        if (u.appVersion.isNotEmpty) 'إصدار التطبيق': u.appVersion,
      },
      data: [
        DataDoc('apps/$appId/users/${u.id}', u.toMap()..removeWhere((k, v) => v == null || v == '' || (v is List && v.isEmpty))),
        ...await _content(appId, u.id, notes),
      ],
      events: events,
      notes: notes,
    );
  }

  /// Posts, stories… that the app saved under the user's record.
  Future<List<DataDoc>> _content(String appId, String uid, List<String> notes) async {
    final out = <DataDoc>[];
    for (final col in const ['posts', 'stories', 'moments', 'comments', 'photos', 'videos']) {
      try {
        for (final d in await _list('$_docs/apps/$appId/users/$uid/$col')) {
          out.add(DataDoc('apps/$appId/users/$uid/$col/${_id(d)}', decodeFields(d['fields'])));
        }
      } catch (_) {}
    }
    return out;
  }

  @override
  Future<void> deleteData(String path) async {
    if (!path.startsWith('apps/') || path.split('/').length <= 4) {
      throw BackendError('حذف هذا السجل غير متاح هنا. استخدم «حذف الحساب».');
    }
    await _send('DELETE', '$_docs/$path');
  }

  @override
  Future<void> addLog(LogEntry e) async {
    await _send('POST', '$_docs/logs', body: {
      'fields': encodeFields({
        'appId': e.appId,
        'userId': e.userId,
        'userName': e.userName,
        'action': e.action,
        'detail': e.detail,
        'by': e.by,
        'at': e.at,
      }),
    });
  }

  @override
  Future<List<LogEntry>> listLogs({int limit = 200}) async {
    final req = http.Request('POST', Uri.parse('$_docs:runQuery'))
      ..headers['Authorization'] = 'Bearer ${await _token()}'
      ..headers['Content-Type'] = 'application/json'
      ..body = jsonEncode({
        'structuredQuery': {
          'from': [{'collectionId': 'logs'}],
          'orderBy': [{'field': {'fieldPath': 'at'}, 'direction': 'DESCENDING'}],
          'limit': limit,
        },
      });
    final res = await http.Response.fromStream(await _http.send(req));
    if (res.statusCode >= 300) throw BackendError('تعذّر تحميل السجل (${res.statusCode})');
    final rows = jsonDecode(utf8.decode(res.bodyBytes)) as List;
    return [
      for (final r in rows)
        if ((r as Map)['document'] != null)
          () {
            final d = r['document'] as Map<String, dynamic>;
            final f = decodeFields(d['fields']);
            return LogEntry(
              id: _id(d),
              appId: '${f['appId'] ?? ''}',
              userId: '${f['userId'] ?? ''}',
              userName: '${f['userName'] ?? ''}',
              action: '${f['action'] ?? ''}',
              detail: '${f['detail'] ?? ''}',
              by: '${f['by'] ?? ''}',
              at: f['at'] is DateTime ? f['at'] as DateTime : DateTime.fromMillisecondsSinceEpoch(0),
            );
          }(),
    ];
  }

  Future<void> _patch(String url, Map<String, Object?> fields, {bool mustExist = false}) async {
    final mask = fields.keys.map((k) => 'updateMask.fieldPaths=$k').join('&');
    final exists = mustExist ? '&currentDocument.exists=true' : '';
    await _send('PATCH', '$url?$mask$exists', body: {'fields': encodeFields(fields)});
  }

  static String _id(Map<String, dynamic> doc) => (doc['name'] as String).split('/').last;

  static Map<String, dynamic> _json(http.Response res) {
    try {
      final v = jsonDecode(utf8.decode(res.bodyBytes));
      return v is Map<String, dynamic> ? v : {};
    } catch (_) {
      return {};
    }
  }

  static String _authError(Map<String, dynamic> body) {
    final code = '${(body['error'] as Map?)?['message'] ?? ''}';
    if (code.contains('INVALID_LOGIN_CREDENTIALS') || code.contains('INVALID_PASSWORD') || code.contains('EMAIL_NOT_FOUND')) {
      return 'الإيميل أو كلمة المرور غير صحيحة';
    }
    if (code.contains('TOO_MANY_ATTEMPTS')) return 'محاولات كثيرة، انتظر قليلاً ثم حاول';
    if (code.contains('USER_DISABLED')) return 'هذا الحساب معطّل';
    if (code.contains('API_KEY') || code.contains('API key')) return 'مفتاح Web API غير صحيح';
    if (code.contains('OPERATION_NOT_ALLOWED')) return 'فعّل تسجيل الدخول بالإيميل وكلمة المرور في Firebase Authentication';
    return code.isEmpty ? 'تعذّر تسجيل الدخول' : 'تعذّر تسجيل الدخول: $code';
  }
}

Map<String, Object?> decodeFields(Object? fields) {
  if (fields is! Map) return {};
  return {for (final e in fields.entries) '${e.key}': decodeValue(e.value)};
}

Object? decodeValue(Object? v) {
  if (v is! Map) return null;
  if (v.containsKey('stringValue')) return v['stringValue'];
  if (v.containsKey('booleanValue')) return v['booleanValue'];
  if (v.containsKey('integerValue')) return int.tryParse('${v['integerValue']}');
  if (v.containsKey('doubleValue')) return (v['doubleValue'] as num).toDouble();
  if (v.containsKey('timestampValue')) return DateTime.tryParse('${v['timestampValue']}')?.toLocal();
  if (v.containsKey('mapValue')) return decodeFields((v['mapValue'] as Map)['fields']);
  if (v.containsKey('arrayValue')) {
    return [for (final x in ((v['arrayValue'] as Map)['values'] as List? ?? const [])) decodeValue(x)];
  }
  return null;
}

Map<String, Object?> encodeFields(Map<String, Object?> fields) =>
    {for (final e in fields.entries) e.key: encodeValue(e.value)};

Map<String, Object?> encodeValue(Object? v) {
  if (v == null) return {'nullValue': null};
  if (v is bool) return {'booleanValue': v};
  if (v is int) return {'integerValue': '$v'};
  if (v is double) return {'doubleValue': v};
  if (v is DateTime) return {'timestampValue': v.toUtc().toIso8601String()};
  if (v is List) return {'arrayValue': {'values': [for (final x in v) encodeValue(x)]}};
  return {'stringValue': '$v'};
}
