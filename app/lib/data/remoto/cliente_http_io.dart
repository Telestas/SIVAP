import 'dart:io';

import 'package:cronet_http/cronet_http.dart';
import 'package:http/http.dart' as http;

/// Android usa la pila de red de Chromium, con HTTP/3 y el proxy del sistema.
/// La caché se desactiva porque este cliente transmite sesiones y datos clínicos.
http.Client crearClienteHttp() {
  if (!Platform.isAndroid) return http.Client();
  final motor = CronetEngine.build(
    cacheMode: CacheMode.disabled,
    enableQuic: true,
    useBuiltInDnsResolver: false,
    userAgent: 'SIVAP-Android',
  );
  return CronetClient.fromCronetEngine(motor, closeEngine: true);
}
