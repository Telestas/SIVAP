import 'dart:io';

import 'package:cronet_http/cronet_http.dart';
import 'package:http/http.dart' as http;

/// Android usa la pila de red de Chromium y el proxy del sistema.
/// La caché se desactiva porque este cliente transmite sesiones y datos clínicos.
http.Client crearClienteHttp() {
  if (!Platform.isAndroid) return http.Client();
  final motor = CronetEngine.build(
    cacheMode: CacheMode.disabled,
    // En la red cubana de prueba Chrome conecta, pero Cronet con QUIC falla
    // antes de recibir HTTP. Probar el mismo origen por TCP (HTTP/2 o HTTP/1.1).
    enableQuic: false,
    useBuiltInDnsResolver: false,
    userAgent: 'SIVAP-Android',
  );
  return CronetClient.fromCronetEngine(motor, closeEngine: true);
}
