import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

/// Usa sockets de dart:io para comparar la ruta TCP con Cronet en Android.
/// HttpClient no mantiene una caché persistente de respuestas clínicas.
http.Client crearClienteHttp() {
  if (!Platform.isAndroid) return http.Client();
  return IOClient(HttpClient()..userAgent = 'SIVAP-Android');
}
