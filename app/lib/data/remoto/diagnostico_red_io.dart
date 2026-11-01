import 'dart:io';

import 'package:cronet_http/cronet_http.dart' as cronet;
import 'package:http/http.dart' as http;

/// Mensajes breves que no incluyen URL con clave, cuerpo ni credenciales.
String? diagnosticoConexion(Object error) {
  if (error is cronet.NetworkException) {
    return diagnosticoCronet(error.errorCode, error.cronetInternalErrorCode);
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
    return 'El teléfono no pudo conectar con sivap.pages.dev. '
        'Compruebe si Chrome puede abrir el panel sin VPN.';
  }
  if (error is HandshakeException || error is TlsException) {
    return 'Falló la conexión segura con sivap.pages.dev (TLS). '
        'Compruebe la fecha y hora del teléfono.';
  }
  return null;
}

/// El código de Cronet distingue el fallo sin exponer la URL ni la cuenta.
String diagnosticoCronet(int codigo, int codigoInterno) {
  final detalle = switch (codigo) {
    1 => 'El teléfono no pudo resolver sivap.pages.dev (DNS).',
    2 => 'Android informa que no tiene conexión a Internet.',
    3 => 'La red del teléfono cambió durante el acceso.',
    4 || 6 => 'La conexión con sivap.pages.dev agotó el tiempo de espera.',
    10 => 'Falló la conexión HTTP/3 con sivap.pages.dev.',
    _ => 'El teléfono no pudo conectar con sivap.pages.dev.',
  };
  return '$detalle Código de red: $codigo/$codigoInterno.';
}
