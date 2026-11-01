import 'dart:async';
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

const _hostDiagnostico = 'sivap.pages.dev';
const _esperaDiagnostico = Duration(seconds: 6);

/// Comprueba etapas de red sin enviar cuenta, contraseña ni token.
Future<String> diagnosticarConexionMovil({
  Future<void> Function()? resolver,
  Future<void> Function()? conectar,
  Future<void> Function()? verificarTls,
  Future<int> Function()? consultar,
}) async {
  final etapas = <String>[];
  for (final (nombre, prueba) in [
    ('DNS', resolver ?? _resolverDiagnostico),
    ('TCP', conectar ?? _conectarDiagnostico),
    ('TLS', verificarTls ?? _verificarTlsDiagnostico),
  ]) {
    try {
      await prueba();
      etapas.add('$nombre OK');
    } on Object catch (error) {
      etapas.add('$nombre falla (${_codigoDiagnostico(error)})');
      return etapas.join(' · ');
    }
  }
  try {
    final estado = await (consultar ?? _consultarDiagnostico)();
    etapas.add('GET HTTP $estado');
  } on Object catch (error) {
    etapas.add('GET falla (${_codigoDiagnostico(error)})');
  }
  return etapas.join(' · ');
}

String _codigoDiagnostico(Object error) {
  if (error is TimeoutException) return 'tiempo agotado';
  if (error is SocketException) {
    final codigo = error.osError?.errorCode;
    return codigo == null ? 'socket' : 'sistema $codigo';
  }
  if (error is HandshakeException || error is TlsException) return 'TLS';
  return 'sin respuesta';
}

Future<void> _resolverDiagnostico() async {
  await InternetAddress.lookup(_hostDiagnostico).timeout(_esperaDiagnostico);
}

Future<void> _conectarDiagnostico() async {
  final socket =
      await Socket.connect(_hostDiagnostico, 443, timeout: _esperaDiagnostico);
  socket.destroy();
}

Future<void> _verificarTlsDiagnostico() async {
  final socket =
      await Socket.connect(_hostDiagnostico, 443, timeout: _esperaDiagnostico);
  try {
    final seguro = await SecureSocket.secure(socket, host: _hostDiagnostico)
        .timeout(_esperaDiagnostico);
    seguro.destroy();
  } finally {
    socket.destroy();
  }
}

Future<int> _consultarDiagnostico() async {
  final cliente = HttpClient()..connectionTimeout = _esperaDiagnostico;
  try {
    final solicitud = await cliente
        .getUrl(Uri.https(_hostDiagnostico, '/api/versiones'))
        .timeout(_esperaDiagnostico);
    final respuesta = await solicitud.close().timeout(_esperaDiagnostico);
    return respuesta.statusCode;
  } finally {
    cliente.close(force: true);
  }
}
