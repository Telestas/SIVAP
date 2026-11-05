import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sivap/data/remoto/diagnostico_transporte.dart';

void main() {
  test('el diagnóstico consulta sin credenciales y excluye IP y otros campos',
      () async {
    final cliente = MockClient((solicitud) async {
      expect(solicitud.method, 'GET');
      expect(solicitud.url.toString(), 'https://sivap.pages.dev/cdn-cgi/trace');
      expect(solicitud.followRedirects, isFalse);
      expect(solicitud.body, isEmpty);
      expect(solicitud.headers.containsKey('authorization'), isFalse);
      expect(solicitud.headers.containsKey('cookie'), isFalse);
      return http.Response('''ip=192.0.2.1
http=http/3
tls=TLSv1.3
sni=encrypted
uag=detalle-privado
''', 200);
    });
    addTearDown(cliente.close);
    final resumen = await consultarTransporte(cliente);
    expect(resumen, 'HTTP 200 · HTTP/3 · TLS 1.3 · SNI cifrado');
    expect(resumen, isNot(contains('192.0.2.1')));
    expect(resumen, isNot(contains('detalle-privado')));
  });

  test('los campos desconocidos y errores HTTP no se reflejan en el resultado',
      () async {
    final cliente = MockClient((_) async =>
        http.Response('http=secreto\ntls=secreto\nsni=secreto', 200));
    addTearDown(cliente.close);
    expect(await consultarTransporte(cliente), isNot(contains('secreto')));
    final rechazado = MockClient((_) async => http.Response('secreto', 403));
    addTearDown(rechazado.close);
    expect(await consultarTransporte(rechazado), 'HTTP 403');
  });
}
