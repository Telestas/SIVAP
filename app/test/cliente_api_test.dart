import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sivap/data/local/seed_data.dart';
import 'package:sivap/data/remoto/cliente_api.dart';
import 'package:sivap/data/remoto/lote.dart';
import 'package:sivap/domain/models/evento_clinico.dart';
import 'package:sivap/domain/models/patient.dart';
import 'package:sivap/domain/models/protocolo.dart';

/// El cliente del servidor central.
///
/// Lo que se comprueba aquí, sobre todo, es que **no llegar** y **que te digan
/// que no** sean dos cosas distintas. Confundirlas produce colas que se
/// reintentan para siempre, o datos que se dan por enviados sin estarlo.
void main() {
  final base = Uri.parse('https://servidor.ejemplo/api');

  /// Un cliente con sesión abierta y un servidor de mentira detrás.
  Future<(ClienteApi, List<http.Request>)> conSesion(
    FutureOr<http.Response> Function(http.Request) responder,
  ) async {
    final vistas = <http.Request>[];
    final api = ClienteApi(
      base: base,
      cliente: MockClient((peticion) async {
        vistas.add(peticion);
        if (peticion.url.path.endsWith('/sesion') &&
            peticion.method == 'POST') {
          return http.Response(
            jsonEncode({
              'token': 'token-de-prueba',
              'expira_en': '2026-10-08T00:00:00Z',
              'investigador': {
                'id': 'u-1',
                'usuario': 'dra.uno',
                'nombre': 'Dra. Uno',
                'institucion': 'HC',
                'roles': ['reclutador'],
              },
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return responder(peticion);
      }),
    );
    await api.abrirSesion(usuario: 'dra.uno', contrasena: 'x');
    return (api, vistas);
  }

  http.Response json(Object cuerpo, [int codigo = 200]) => http.Response(
      jsonEncode(cuerpo), codigo, headers: {'content-type': 'application/json'});

  group('sesión', () {
    test('abrir sesión guarda el token y lo manda en las siguientes', () async {
      final (api, vistas) =
          await conSesion((_) async => json({'instituciones': []}));

      await api.configuracionEstudio();

      expect(api.haySesion, isTrue);
      expect(vistas.last.headers['Authorization'], 'Bearer token-de-prueba');
      expect(vistas.last.url.toString(), 'https://servidor.ejemplo/api/estudio');
    });

    test('sin sesión no se intenta ni la llamada', () async {
      var llamadas = 0;
      final api = ClienteApi(
        base: base,
        cliente: MockClient((_) async {
          llamadas++;
          return json(const {});
        }),
      );

      await expectLater(
          api.configuracionEstudio(), throwsA(isA<SesionCaducada>()));
      expect(llamadas, 0);
    });

    test('un 401 olvida el token, para que nadie siga con él', () async {
      final (api, _) = await conSesion(
          (_) async => json({'detail': 'Sesión no válida o caducada.'}, 401));

      await expectLater(
          api.configuracionEstudio(), throwsA(isA<SesionCaducada>()));
      expect(api.haySesion, isFalse);
    });
  });

  group('no llegar es distinto de que te digan que no', () {
    test('un fallo de red es SinConexion, y se reintenta', () async {
      final (api, _) = await conSesion(
          (_) async => throw const SocketExceptionFalsa('sin ruta al host'));

      await expectLater(
          api.configuracionEstudio(), throwsA(isA<SinConexion>()));
    });

    test('agotar el tiempo también es SinConexion', () async {
      final api = ClienteApi(
        base: base,
        tiempoLimite: const Duration(milliseconds: 30),
        cliente: MockClient((_) async {
          await Future<void>.delayed(const Duration(seconds: 5));
          return json(const {});
        }),
      );

      await expectLater(
        api.abrirSesion(usuario: 'x', contrasena: 'y'),
        throwsA(isA<SinConexion>()),
      );
    });

    test('un 409 es del servidor, y reintentarlo repetiría el error', () async {
      final (api, _) = await conSesion((_) async => json(
          {'detail': 'La secuencia de aleatorización está agotada.'}, 409));

      await expectLater(
        api.pedirTramo('d-1'),
        throwsA(isA<ErrorDelServidor>().having(
            (e) => e.detalle, 'detalle', contains('agotada'))),
      );
    });

    test('el motivo de un 422 llega legible', () async {
      // FastAPI devuelve una lista de errores de validación; en el teléfono
      // hace falta una frase, no una estructura.
      final (api, _) = await conSesion((_) async => json({
            'detail': [
              {'msg': 'el tipo de evento no existe'},
              {'msg': 'la fecha no es una fecha'},
            ]
          }, 422));

      await expectLater(
        api.configuracionEstudio(),
        throwsA(isA<ErrorDelServidor>().having((e) => e.detalle, 'detalle',
            'el tipo de evento no existe · la fecha no es una fecha')),
      );
    });
  });

  group('el tramo de la secuencia', () {
    Tramo tramo({int desde = 1, int hasta = 26, int consumidas = 0}) =>
        Tramo.desdeJson({
          'desde': desde,
          'hasta': hasta,
          'consumidas': consumidas,
          'codigo_binario': '0101010101' * ((hasta - desde) ~/ 10 + 1),
          'asignado_en': '2026-09-01T10:00:00Z',
        });

    test('la siguiente posición avanza con lo consumido', () {
      expect(tramo().siguientePosicion, 1);
      expect(tramo(consumidas: 3).siguientePosicion, 4);
    });

    test('un tramo agotado no ofrece posición, y ahí hay que parar', () {
      // Sin posición y sin conexión para pedir otro tramo, se deja de enrolar.
      // Improvisar una asignación es lo que la aleatorización pre-generada
      // existe para evitar.
      final agotado = tramo(desde: 1, hasta: 4, consumidas: 3);

      expect(agotado.libres, 0);
      expect(agotado.siguientePosicion, isNull);
    });

    test('la rama sale del bit de esa posición, no de otra', () {
      // Bits «0101…» desde la posición 50: par → A, impar → B.
      final t = Tramo.desdeJson({
        'desde': 50,
        'hasta': 54,
        'consumidas': 0,
        'codigo_binario': '0101',
        'asignado_en': '2026-09-01T10:00:00Z',
      });

      expect(t.protocoloEn(50), Protocolo.a);
      expect(t.protocoloEn(51), Protocolo.b);
      expect(t.protocoloEn(53), Protocolo.b);
      // Fuera del tramo no hay respuesta que dar.
      expect(t.protocoloEn(49), isNull);
      expect(t.protocoloEn(54), isNull);
    });
  });

  group('la forma del lote', () {
    final paciente = Patient(
      id: 'c0ffee00-0000-4000-8000-000000000001',
      codigo: 'HC-041',
      nombre: 'Nombre Inventado',
      numeroHistoriaClinica: 'HC-9',
      telefonoPrincipal: '55512345',
      institucion: Seed.coordinador,
      edad: 62,
      sexo: Sexo.masculino,
      protocolo: Protocolo.a,
      secuencia: 'prueba',
      posicionSecuencia: 41,
      asignadoEn: DateTime.utc(2026, 9, 1, 10),
      recolectorId: 'u-1',
      enroladoEn: DateTime.utc(2026, 9, 1, 10),
    );

    final evento = EventoClinico(
      id: 'c0ffee00-0000-4000-8000-000000000002',
      patientId: paciente.id,
      tipo: TipoEvento.pruebaVentilacionEspontanea,
      ocurrencia: 2,
      fechaOcurrencia: DateTime.utc(2026, 9, 2),
      estado: EstadoEvento.registrado,
      sync: SyncStatus.enCola,
      valores: const {
        'metodo_pve': 'Tubo en T',
        'test_fuga': true,
        'comorbilidades': ['HTA', 'DM'],
      },
      recolectorId: 'u-1',
      institucion: Seed.coordinador,
      fechaCaptura: DateTime.utc(2026, 9, 2, 14, 30),
    );

    test('el tipo de evento viaja como lo nombra el esquema', () {
      final json = EventoEnviable(evento, const {}).aJson();

      // Dart nombra en camello, PostgreSQL en snake. Si esto se desalinea, el
      // servidor rechaza el lote entero con un 422.
      expect(json['tipo'], 'prueba_ventilacion_espontanea');
    });

    test('la fecha de ocurrencia va sin hora, que es lo que guarda', () {
      expect(EventoEnviable(evento, const {}).aJson()['fecha_ocurrencia'],
          '2026-09-02');
    });

    test('los valores viajan como texto, con su tipo declarado al lado', () {
      final valores = EventoEnviable(evento, const {
        'metodo_pve': 'lista',
        'test_fuga': 'booleano',
        'comorbilidades': 'lista',
      }).aJson()['valores'] as List;

      expect(valores, hasLength(3));
      expect(
        valores.firstWhere((v) => v['campo'] == 'test_fuga'),
        {'campo': 'test_fuga', 'tipo': 'booleano', 'valor': 'true'},
      );
      expect(
        valores.firstWhere((v) => v['campo'] == 'comorbilidades')['valor'],
        'HTA · DM',
      );
    });

    test('la identidad va en su propio bloque, no suelta en el paciente', () {
      final json = PacienteEnviable(paciente).aJson();

      // CLAUDE.md §1: así el servidor guarda el dataset clínico sin ella.
      expect(json.keys, isNot(contains('nombre')));
      expect((json['identidad']! as Map)['nombre'], 'Nombre Inventado');
      expect((json['asignacion']! as Map)['posicion'], 41);
      expect((json['asignacion']! as Map)['protocolo'], 'a');
    });

    test('el lote cuenta sus registros como los cuenta el servidor', () {
      final lote = Lote(
        dispositivoId: 'd-1',
        pacientes: [PacienteEnviable(paciente)],
        eventos: [EventoEnviable(evento, const {})],
      );

      // Un paciente, un evento y sus tres valores.
      expect(lote.registros, 5);
      expect(lote.vacio, isFalse);
    });

    test('reenviar el mismo lote conserva su identificador', () {
      final lote = Lote(dispositivoId: 'd-1', id: 'lote-1');

      expect(lote.aJson()['id'], 'lote-1');
      // Y uno nuevo se genera solo, en el formato que el servidor acepta.
      expect(Lote(dispositivoId: 'd-1').id, matches(RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-'
          r'[0-9a-f]{12}$')));
    });

    test('se envía tal cual y el servidor contesta qué entró', () async {
      Map<String, dynamic>? recibido;
      final (api, _) = await conSesion((peticion) async {
        recibido = jsonDecode(peticion.body) as Map<String, dynamic>;
        return json({
          'lote_id': recibido!['id'],
          'registros': 2,
          'aceptados': 1,
          'rechazados': 1,
          'detalle': [
            {
              'tipo': 'paciente',
              'id': paciente.id,
              'motivo': 'duplicate key value violates unique constraint',
            }
          ],
          'ya_recibido': false,
        });
      });

      final resultado = await api.enviar(Lote(
        dispositivoId: 'd-1',
        pacientes: [PacienteEnviable(paciente)],
      ));

      expect(recibido!['dispositivo_id'], 'd-1');
      expect(resultado.todoEntro, isFalse);
      // Lo rechazado no se da por enviado; lo demás sí.
      expect(resultado.idsRechazados, {paciente.id});
      expect(resultado.detalle.single.tipo, 'paciente');
    });

    test('un lote ya recibido se reconoce como tal', () async {
      final (api, _) = await conSesion((_) async => json({
            'lote_id': 'lote-1',
            'registros': 4,
            'aceptados': 4,
            'rechazados': 0,
            'detalle': [],
            'ya_recibido': true,
          }));

      final resultado =
          await api.enviar(Lote(dispositivoId: 'd-1', id: 'lote-1'));

      expect(resultado.yaRecibido, isTrue);
      expect(resultado.todoEntro, isTrue);
    });
  });
}

/// Un fallo de red cualquiera. No se usa `SocketException` de `dart:io` porque
/// no existe en el navegador, y la app también compila para ahí.
class SocketExceptionFalsa implements Exception {
  const SocketExceptionFalsa(this.mensaje);
  final String mensaje;

  @override
  String toString() => mensaje;
}
