import 'dart:io';

import 'package:cronet_http/cronet_http.dart' as cronet;
import 'package:http/http.dart' as http;

/// Mensajes breves que no incluyen URL con clave, cuerpo ni credenciales.
String? diagnosticoConexion(Object error) {
  if (error is cronet.NetworkException) {
    return 'Falló la conexión con sivap.pages.dev. '
        'Código de red: ${error.errorCode}/${error.cronetInternalErrorCode}.';
  }
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
    if (detalle.contains('connection reset')) {
      final codigo = error is SocketException ? error.osError?.errorCode : null;
      final sufijo = codigo == null ? '' : ' Código de sistema: $codigo.';
      return 'La conexión con sivap.pages.dev se cerró antes de recibir '
          'respuesta (TCP reset).$sufijo';
    }
    if (detalle.contains('connection closed before full header was received')) {
      return 'La conexión con sivap.pages.dev se cerró antes de recibir '
          'la respuesta HTTP.';
    }
    if (error is SocketException && error.osError != null) {
      return 'El teléfono no pudo conectar con sivap.pages.dev. '
          'Código de sistema: ${error.osError!.errorCode}.';
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
