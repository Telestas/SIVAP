import 'dart:io';

import 'package:cronet_http/cronet_http.dart';
import 'package:http/http.dart' as http;

/// Indica HTTP/3 desde el primer acceso, sin esperar un Alt-Svc recibido por TCP.
/// La caché permanece desactivada para sesiones y datos clínicos.
http.Client crearClienteHttp() {
  if (!Platform.isAndroid) return http.Client();
  final motor = CronetEngine.build(
    cacheMode: CacheMode.disabled,
    enableQuic: true,
    useBuiltInDnsResolver: true,
    quicHints: [('sivap.pages.dev', 443, 443)],
    userAgent: 'SIVAP-Android',
  );
  return CronetClient.fromCronetEngine(motor, closeEngine: true);
}
