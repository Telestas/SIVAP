import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sivap/data/remoto/diagnostico_red_io.dart';

void main() {
  test('el diagnóstico detiene las pruebas en la etapa que falla', () async {
    final llamadas = <String>[];
    final resultado = await diagnosticarConexionMovil(
      resolver: () async => llamadas.add('DNS'),
      conectar: () async => llamadas.add('TCP'),
      verificarTls: () async {
        llamadas.add('TLS');
        throw const SocketException(
          'Connection reset by peer: key=secreto',
          osError: OSError('Connection reset by peer', 104),
        );
      },
      consultar: () async {
        llamadas.add('GET');
        return 200;
      },
    );

    expect(llamadas, ['DNS', 'TCP', 'TLS']);
    expect(resultado, 'DNS OK · TCP OK · TLS falla (sistema 104)');
    expect(resultado, isNot(contains('secreto')));
  });

  test('la petición sin credenciales informa el estado HTTP', () async {
    final resultado = await diagnosticarConexionMovil(
      resolver: () async {},
      conectar: () async {},
      verificarTls: () async {},
      consultar: () async => 200,
    );

    expect(resultado, 'DNS OK · TCP OK · TLS OK · GET HTTP 200');
  });
}
