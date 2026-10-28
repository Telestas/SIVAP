import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:web/web.dart' as web;

/// Configura Firestore antes de que se abra cualquier colección en Pages.
void configurarProxyFirestoreWeb() {
  final host = web.window.location.host;
  if (!web.window.location.hostname.endsWith('.pages.dev')) {
    return;
  }
  FirebaseFirestore.instance.settings = Settings(
    host: host,
    sslEnabled: true,
    webExperimentalForceLongPolling: true,
  );
}
