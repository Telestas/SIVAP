import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:sivap/data/remoto/sincronizacion.dart';

void main() {
  test('una página HTML nunca se muestra como excepción de aleatorización', () {
    final respuesta = http.Response('<html><head>Error</head></html>', 404,
        headers: {'content-type': 'text/html'});
    final mensaje = mensajeRespuestaTramo(respuesta);
    expect(mensaje, contains('aún no está publicado'));
    expect(mensaje, isNot(contains('<html>')));
  });

  test('una respuesta JSON del servicio puede procesarse', () {
    final respuesta = http.Response('{"result":{}}', 200,
        headers: {'content-type': 'application/json'});
    expect(mensajeRespuestaTramo(respuesta), isNull);
  });
}
