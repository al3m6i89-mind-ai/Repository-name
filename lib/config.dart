import 'package:shared_preferences/shared_preferences.dart';

import 'backend/backend.dart';
import 'backend/demo_backend.dart';
import 'backend/firebase_backend.dart';

/// Which backend to use, remembered between launches.
class HubConfig {
  bool demo;
  String apiKey;
  String projectId;
  String lastEmail;

  HubConfig({this.demo = true, this.apiKey = '', this.projectId = '', this.lastEmail = ''});

  bool get firebaseReady => apiKey.trim().isNotEmpty && projectId.trim().isNotEmpty;

  AdminBackend createBackend() =>
      demo ? DemoBackend() : FirebaseBackend(apiKey: apiKey.trim(), projectId: projectId.trim());

  static Future<HubConfig> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      return HubConfig(
        demo: p.getBool('demo') ?? true,
        apiKey: p.getString('apiKey') ?? '',
        projectId: p.getString('projectId') ?? '',
        lastEmail: p.getString('lastEmail') ?? '',
      );
    } catch (_) {
      return HubConfig();
    }
  }

  Future<void> save() async {
    final p = await SharedPreferences.getInstance();
    await p.setBool('demo', demo);
    await p.setString('apiKey', apiKey);
    await p.setString('projectId', projectId);
    await p.setString('lastEmail', lastEmail);
  }
}
