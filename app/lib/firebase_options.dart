import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';

/// Configuración pública de los clientes Firebase de SIVAP.
///
/// Las API keys de Firebase identifican el proyecto y se distribuyen dentro de
/// toda app cliente; no autorizan acceso a datos. La autorización depende de
/// Firebase Authentication, App Check y las reglas de Firestore. Nunca añada
/// aquí cuentas de servicio, tokens administrativos ni contraseñas.
class FirebaseSivapOptions {
  const FirebaseSivapOptions._();

  static FirebaseOptions get actual {
    if (kIsWeb) return _web;
    if (defaultTargetPlatform == TargetPlatform.android) return _android;
    throw UnsupportedError(
        'Firebase aún no está configurado para $defaultTargetPlatform.');
  }

  static const FirebaseOptions _android = FirebaseOptions(
    apiKey: 'AIzaSyB7TWQLo-RvWIF3y9TBL3HFvUiKo3nNFiA',
    appId: '1:388763509104:android:c374ff2648bb0f0771afb5',
    messagingSenderId: '388763509104',
    projectId: 'sivap-f5060',
    storageBucket: 'sivap-f5060.firebasestorage.app',
  );

  static const FirebaseOptions _web = FirebaseOptions(
    apiKey: 'AIzaSyDDk4UqDn-wYhAjSnI4WR4N3K79NjhA8Tg',
    appId: '1:388763509104:web:7d3e2c8bf8ffe80171afb5',
    messagingSenderId: '388763509104',
    projectId: 'sivap-f5060',
    authDomain: 'sivap-f5060.firebaseapp.com',
    storageBucket: 'sivap-f5060.firebasestorage.app',
    measurementId: 'G-ZYLGN2VLNX',
  );
}
