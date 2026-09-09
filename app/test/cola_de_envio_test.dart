import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sivap/data/local/in_memory_study_repository.dart';
import 'package:sivap/data/local/seed_data.dart';
import 'package:sivap/data/remoto/cliente_api.dart';
import 'package:sivap/data/remoto/cola_de_envio.dart';
import 'package:sivap/domain/models/evento_clinico.dart';
import 'package:sivap/domain/models/patient.dart';

/// La cola de envío.
///
/// Lo que importa aquí no es que envíe: es qué da por enviado. Marcar de más
/// pierde datos en silencio, que es el peor fallo posible en un sistema como
/// este; marcar de menos solo duplica trabajo, y el servidor lo absorbe porque
/// cada registro es idempotente.
void main() {
  late InMemoryStudyRepository repo;
  late List<Map<String, dynamic>> enviados;

  setUp(() {
    repo = InMemoryStudyRepository();
    enviados = [];
  });

  /// Una cola contra un servidor de mentira que responde lo que se le diga.
  ColaDeEnvio cola(
    Future<http.Response> Function(Map<String, dynamic> lote) responder,
  ) {
    final api = ClienteApi(
      base: Uri.parse('https://servidor.ejemplo/api'),
      cliente: MockClient((peticion) async {
        if (peticion.url.path.endsWith('/sesion')) {
          return http.Response(
              jsonEncode({
                'token': 't',
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
              headers: {'content-type': 'application/json'});
        }
        final lote = jsonDecode(peticion.body) as Map<String, dynamic>;
        enviados.add(lote);
        return responder(lote);
      }),
    );
    return ColaDeEnvio(repo: repo, api: api, dispositivoId: 'd-1');
  }

  Future<void> abrirSesion(ColaDeEnvio c) =>
      (c.api as ClienteApi).abrirSesion(usuario: 'dra.uno', contrasena: 'x');

  /// Acepta el lote entero.
  http.Response todoBien(Map<String, dynamic> lote) => http.Response(
      jsonEncode({
        'lote_id': lote['id'],
        'registros': 0,
        'aceptados': 0,
        'rechazados': 0,
        'detalle': const [],
        'ya_recibido': false,
      }),
      200,
      headers: {'content-type': 'application/json'});

  Patient enrolar() => repo.enrolar(
        autor: Seed.reclutador,
        institucion: Seed.coordinador,
        nombre: 'Nombre Inventado',
        numeroHistoriaClinica: 'HC-9',
        telefonoPrincipal: '55512345',
        edad: 62,
        sexo: Sexo.masculino,
      );

  group('qué entra en la cola', () {
    test('los datos de demostración no se envían nunca', () {
      // Están cargados —la app arranca con ellos— y aun así la cola está
      // vacía. Sus identificadores no son UUID a propósito, y esa es la
      // propiedad que los mantiene fuera.
      expect(repo.pacientes(), isNotEmpty);

      expect(repo.pendienteDeEnvio().vacio, isTrue);
    });

    test('un paciente enrolado de verdad sí entra', () {
      final paciente = enrolar();

      final pendiente = repo.pendienteDeEnvio();
      expect(pendiente.pacientes.map((p) => p.id), contains(paciente.id));
    });

    test('un borrador no se envía', () {
      final paciente = enrolar();
      repo.registrarConsentimiento(
          autor: Seed.reclutador, patientId: paciente.id, firmaTrazos: const []);
      repo.guardarBorrador(
        autor: Seed.reclutador,
        patientId: paciente.id,
        tipo: TipoEvento.enrolamiento,
        fechaOcurrencia: DateTime(2026, 9, 2),
        valores: const {'fecha_ingreso_uci': '2026-09-01'},
      );

      // Sincronizar datos a medio teclear llenaría el estudio de registros que
      // nadie sabría si son definitivos.
      expect(repo.pendienteDeEnvio().eventos, isEmpty);
    });

    test('el mismo evento, ya registrado, sí entra', () {
      final paciente = enrolar();
      repo.registrarConsentimiento(
          autor: Seed.reclutador, patientId: paciente.id, firmaTrazos: const []);
      final evento = repo.registrarEvento(
        autor: Seed.reclutador,
        patientId: paciente.id,
        tipo: TipoEvento.enrolamiento,
        fechaOcurrencia: DateTime(2026, 9, 2),
        valores: const {'fecha_ingreso_uci': '2026-09-01'},
      );

      expect(repo.pendienteDeEnvio().eventos.map((e) => e.id),
          contains(evento.id));
    });
  });

  group('qué se da por enviado', () {
    test('sin nada pendiente no se llama al servidor', () async {
      final c = cola((_) async => todoBien(const {}));
      await abrirSesion(c);

      final resultado = await c.sincronizar();

      expect(resultado, isA<NadaQueEnviar>());
      expect(enviados, isEmpty);
    });

    test('lo aceptado se marca y deja de estar pendiente', () async {
      final paciente = enrolar();
      final c = cola((lote) async => todoBien(lote));
      await abrirSesion(c);

      final resultado = await c.sincronizar();

      expect(resultado, isA<Hecho>());
      expect(enviados.single['pacientes'], hasLength(1));
      expect(repo.pendienteDeEnvio().vacio, isTrue);
      // Y no se vuelve a enviar.
      expect(await c.sincronizar(), isA<NadaQueEnviar>());
      expect(enviados, hasLength(1));
      expect(paciente.id, isNotEmpty);
    });

    test('lo rechazado se queda en la cola, con su motivo', () async {
      final paciente = enrolar();
      final c = cola((lote) async => http.Response(
          jsonEncode({
            'lote_id': lote['id'],
            'registros': 1,
            'aceptados': 0,
            'rechazados': 1,
            'detalle': [
              {
                'tipo': 'paciente',
                'id': paciente.id,
                'motivo': 'El centro HC no tiene aprobación del Comité de Ética',
              }
            ],
            'ya_recibido': false,
          }),
          200,
          headers: {'content-type': 'application/json'}));
      await abrirSesion(c);

      final resultado = await c.sincronizar();

      // Descartarlo en silencio sería perderlo. Se queda, y entra solo en
      // cuanto el motivo del rechazo desaparezca.
      expect(repo.pendienteDeEnvio().pacientes.map((p) => p.id),
          contains(paciente.id));
      expect(resultado.mensaje, contains('sin entrar'));
    });

    test('un lote con parte rechazada marca solo la parte que entró', () async {
      final paciente = enrolar();
      repo.registrarConsentimiento(
          autor: Seed.reclutador, patientId: paciente.id, firmaTrazos: const []);
      final evento = repo.registrarEvento(
        autor: Seed.reclutador,
        patientId: paciente.id,
        tipo: TipoEvento.enrolamiento,
        fechaOcurrencia: DateTime(2026, 9, 2),
        valores: const {'fecha_ingreso_uci': '2026-09-01'},
      );

      final c = cola((lote) async => http.Response(
          jsonEncode({
            'lote_id': lote['id'],
            'registros': 3,
            'aceptados': 2,
            'rechazados': 1,
            'detalle': [
              {'tipo': 'evento', 'id': evento.id, 'motivo': 'clave duplicada'}
            ],
            'ya_recibido': false,
          }),
          200,
          headers: {'content-type': 'application/json'}));
      await abrirSesion(c);

      await c.sincronizar();

      final pendiente = repo.pendienteDeEnvio();
      expect(pendiente.pacientes, isEmpty);
      expect(pendiente.eventos.map((e) => e.id), [evento.id]);
    });
  });

  group('no llegar no es que te digan que no', () {
    test('sin conexión no se marca nada y se reintenta', () async {
      enrolar();
      final c = cola((_) async => throw const _FalloDeRed());
      await abrirSesion(c);

      final resultado = await c.sincronizar();

      expect(resultado, isA<SinRed>());
      expect(resultado.seReintenta, isTrue);
      // Intacta: nadie ha dicho que esto llegara.
      expect(repo.pendienteDeEnvio().vacio, isFalse);
    });

    test('un rechazo del lote entero no se reintenta a ciegas', () async {
      enrolar();
      final c = cola((_) async => http.Response(
          jsonEncode({'detail': 'el tipo de evento no existe'}), 422,
          headers: {'content-type': 'application/json'}));
      await abrirSesion(c);

      final resultado = await c.sincronizar();

      expect(resultado, isA<Rechazado>());
      expect(resultado.seReintenta, isFalse);
      expect(repo.pendienteDeEnvio().vacio, isFalse);
    });

    test('con la sesión caducada se pide volver a entrar', () async {
      enrolar();
      final c = cola((_) async => http.Response(
          jsonEncode({'detail': 'Sesión no válida o caducada.'}), 401,
          headers: {'content-type': 'application/json'}));
      await abrirSesion(c);

      final resultado = await c.sincronizar();

      expect(resultado, isA<SesionPerdida>());
      expect(resultado.mensaje, contains('caducó'));
      expect(repo.pendienteDeEnvio().vacio, isFalse);
    });
  });

  group('lo que viaja', () {
    test('cada valor lleva declarado su tipo, sacado de la definición',
        () async {
      final paciente = enrolar();
      repo.registrarConsentimiento(
          autor: Seed.reclutador, patientId: paciente.id, firmaTrazos: const []);
      repo.registrarEvento(
        autor: Seed.reclutador,
        patientId: paciente.id,
        tipo: TipoEvento.enrolamiento,
        fechaOcurrencia: DateTime(2026, 9, 2),
        valores: const {
          'fecha_ingreso_uci': '2026-09-01',
          'peso': 88,
          'via_aerea_dificil': true,
          'comorbilidades': ['HTA'],
        },
      );
      final c = cola((lote) async => todoBien(lote));
      await abrirSesion(c);

      await c.sincronizar();

      final valores =
          (enviados.single['eventos'] as List).single['valores'] as List;
      Map tipoDe(String campo) =>
          valores.firstWhere((v) => v['campo'] == campo) as Map;

      // El servidor no adivina: un «30» puede ser un número o el texto de una
      // opción, y en el dataset exportado esa diferencia importa.
      expect(tipoDe('fecha_ingreso_uci')['tipo'], 'fecha');
      expect(tipoDe('peso')['tipo'], 'numero');
      expect(tipoDe('via_aerea_dificil')['tipo'], 'booleano');
      expect(tipoDe('comorbilidades')['tipo'], 'lista');
    });

    test('la corrección de un evento vuelve a la cola con su auditoría',
        () async {
      final paciente = enrolar();
      repo.registrarConsentimiento(
          autor: Seed.reclutador, patientId: paciente.id, firmaTrazos: const []);
      final evento = repo.registrarEvento(
        autor: Seed.reclutador,
        patientId: paciente.id,
        tipo: TipoEvento.enrolamiento,
        fechaOcurrencia: DateTime(2026, 9, 2),
        valores: const {'peso': 88},
      );
      final c = cola((lote) async => todoBien(lote));
      await abrirSesion(c);
      await c.sincronizar();
      expect(repo.pendienteDeEnvio().vacio, isTrue);

      repo.corregirEventoRegistrado(
        autor: Seed.principal,
        eventoId: evento.id,
        campo: 'peso',
        valorNuevo: 68,
        motivo: 'cifras transpuestas al teclear',
      );

      // El evento ya lo tiene el servidor; lo que falta por enviar es la
      // corrección, que es lo que cuenta qué cambió y por qué.
      final pendiente = repo.pendienteDeEnvio();
      expect(pendiente.auditoria, hasLength(1));
      expect(pendiente.auditoria.single.motivo,
          'cifras transpuestas al teclear');
    });
  });
}

class _FalloDeRed implements Exception {
  const _FalloDeRed();

  @override
  String toString() => 'sin ruta al host';
}
