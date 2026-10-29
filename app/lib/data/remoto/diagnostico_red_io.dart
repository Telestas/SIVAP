import 'dart:io';

import 'package:http/http.dart' as http;

/// Mensajes breves que no incluyen URL con clave, cuerpo ni credenciales.
String? diagnosticoConexion(Object error) {
  final texto =
      error is http.ClientException ? error.message : error.toString();
  if (error is SocketException || error is http.ClientException) {
    final detalle = texto.toLowerCase();
    if (detalle.contains('failed host lookup') ||
        detalle.contains('name or service not known') ||
        detalle.contains('no address associated')) {
      return 'El teléfono no pudo resolver sivap.pages.dev (DNS). '
          'Compruebe si Chrome puede abrir el panel sin VPN.';
    }
    if (detalle.contains('handshake') || detalle.contains('certificate')) {
      return 'Falló la conexión segura con sivap.pages.dev (TLS). '
          'Compruebe la fecha y hora del teléfono.';
    }
    return 'El teléfono no pudo conectar con sivap.pages.dev. '
        'Compruebe si Chrome puede abrir el panel sin VPN.';
  }
  if (error is HandshakeException || error is TlsException) {
    return 'Falló la conexión segura con sivap.pages.dev (TLS). '
        'Compruebe la fecha y hora del teléfono.';
  }
  return null;
}
