import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sivap/data/remoto/diagnostico_red_io.dart';

void main() {
  test('un fallo TLS de Dart no impide probar la ruta real de la app',
      () async {
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
      consultarRutaApp: () async {
        llamadas.add('APP');
        return 'HTTP 200 · HTTP/3 · TLS 1.3 · SNI cifrado';
      },
    );

    expect(llamadas, ['DNS', 'TCP', 'TLS', 'APP']);
    expect(resultado, contains('Ruta app: HTTP 200 · HTTP/3'));
    expect(resultado, contains('TCP de Dart: DNS OK · TCP OK · TLS falla'));
    expect(resultado, isNot(contains('secreto')));
  });

  test('el diagnóstico distingue el fallo HTTP del transporte de la app',
      () async {
    final resultado = await diagnosticarConexionMovil(
      resolver: () async {},
      conectar: () async {},
      verificarTls: () async {},
      consultarRutaApp: () async => 'HTTP 502',
    );

    expect(resultado,
        'Ruta app: HTTP 502.\nTCP de Dart: DNS OK · TCP OK · TLS OK');
  });
}
