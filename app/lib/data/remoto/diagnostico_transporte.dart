import 'package:http/http.dart' as http;

/// Consulta el transporte sin enviar credenciales ni seguir redirecciones.
/// La traza contiene IP: solo se devuelve una lista cerrada de campos de red.
Future<String> consultarTransporte(http.Client cliente,
    {Future<void>? cancelacion}) async {
  final solicitud = http.AbortableRequest(
      'GET', Uri.https('sivap.pages.dev', '/cdn-cgi/trace'),
      abortTrigger: cancelacion)
    ..followRedirects = false;
  final respuesta = await cliente.send(solicitud);
  if (respuesta.statusCode != 200) return 'HTTP ${respuesta.statusCode}';
  final datos = <int>[];
  await for (final bloque in respuesta.stream) {
    datos.addAll(bloque);
    if (datos.length > 8192) {
      throw const FormatException('Traza demasiado larga');
    }
  }
  final campos = <String, String>{};
  for (final linea in String.fromCharCodes(datos).split('\n')) {
    final corte = linea.indexOf('=');
    if (corte > 0) {
      campos[linea.substring(0, corte)] = linea.substring(corte + 1).trim();
    }
  }
  final protocolo = switch (campos['http']) {
    'http/3' => 'HTTP/3',
    'http/2' => 'HTTP/2',
    'http/1.1' => 'HTTP/1.1',
    _ => 'protocolo no informado',
  };
  final tls = switch (campos['tls']) {
    'TLSv1.3' => 'TLS 1.3',
    'TLSv1.2' => 'TLS 1.2',
    _ => 'TLS no informado',
  };
  final sni = switch (campos['sni']) {
    'encrypted' => 'SNI cifrado',
    'plaintext' => 'SNI visible',
    _ => 'SNI no informado',
  };
  return 'HTTP 200 · $protocolo · $tls · $sni';
}
