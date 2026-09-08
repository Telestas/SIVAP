import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sivap/data/local/in_memory_study_repository.dart';
import 'package:sivap/data/local/seed_data.dart';
import 'package:sivap/data/remoto/cliente_api.dart';
import 'package:sivap/data/remoto/cola_de_envio.dart';
import 'package:sivap/data/remoto/sincronizacion.dart';
import 'package:sivap/domain/models/patient.dart';

/// La sincronización tal como la usa la app.
///
/// El detalle que más importa aquí es el identificador del aparato. Si se
/// regenerara en cada arranque, el servidor vería un dispositivo nuevo cada vez
/// y le entregaría un tramo nuevo de la secuencia de aleatorización — quemando
/// posiciones que nadie va a usar y dejando huecos permanentes en el estudio.
void main() {
  late InMemoryStudyRepository repo;
  late List<http.Request> vistas;

  setUp(() {
    repo = InMemoryStudyRepository();
    vistas = [];
  });

  http.Response json(Object cuerpo, [int codigo = 200]) => http.Response(
      jsonEncode(cuerpo), codigo, headers: {'content-type': 'application/json'});

  http.Response sesionAbierta() => json({
        'token': 't',
        'expira_en': '2026-10-08T00:00:00Z',
        'investigador': {
          'id': 'u-1',
          'usuario': 'dra.uno',
          'nombre': 'Dra. Uno',
          'institucion': 'HC',
          'roles': ['reclutador', 'aplicador'],
        },
      });

  Sincronizacion sync({
    http.Response Function(http.Request)? responder,
  }) =>
      Sincronizacion(
        repo,
        construirCliente: (base) => ClienteApi(
          base: base,
          cliente: MockClient((peticion) async {
            vistas.add(peticion);
            if (peticion.url.path.endsWith('/sesion')) return sesionAbierta();
            return responder?.call(peticion) ?? json(const {});
          }),
        ),
      );

  Patient enrolar() => repo.enrolar(
        autor: Seed.reclutador,
        institucion: Seed.coordinador,
        nombre: 'Nombre Inventado',
        numeroHistoriaClinica: 'HC-9',
        telefonoPrincipal: '55512345',
        edad: 62,
        sexo: Sexo.masculino,
      );

  group('identidad del aparato', () {
    test('se crea una vez y se guarda', () {
      final primera = sync();

      expect(primera.dispositivoId, isNotEmpty);
      expect(repo.ajuste(Sincronizacion.claveDispositivo),
          primera.dispositivoId);
    });

    test('sobrevive a reabrir la app', () {
      // Dos instancias sobre el mismo almacén son dos arranques. El servidor
      // tiene que ver el mismo aparato, no dos.
      final primera = sync();

      final segunda = sync();

      expect(segunda.dispositivoId, primera.dispositivoId);
    });

    test('viaja en el formato que el servidor acepta', () {
      // El esquema central declara `uuid`: un identificador con otra forma
      // haría rechazar el lote entero.
      expect(sync().dispositivoId, matches(RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-'
          r'[0-9a-f]{12}$')));
    });
  });

  group('a qué servidor habla', () {
    test('sin configurar, no se intenta nada y se dice por qué', () async {
      enrolar();
      final s = sync();

      final resultado = await s.sincronizar();

      expect(s.configurado, isFalse);
      expect(resultado, isA<SinRed>());
      expect(resultado.mensaje, contains('Sin conexión'));
      expect(vistas, isEmpty);
      // Y lo pendiente sigue pendiente: nadie ha dicho que llegara.
      expect(s.pendientes, greaterThan(0));
    });

    test('la dirección se guarda para el próximo arranque', () {
      sync().configurar('https://servidor.ejemplo/api');

      expect(repo.ajuste(Sincronizacion.claveServidor),
          'https://servidor.ejemplo/api');
      expect(sync().servidor.toString(), 'https://servidor.ejemplo/api');
    });
  });

  group('entrar en el servidor', () {
    test('abre sesión y da de alta el aparato', () async {
      final s = sync()..configurar('https://servidor.ejemplo/api');

      final error = await s.entrar('dra.uno', 'clave');

      expect(error, isNull);
      expect(s.haySesion, isTrue);
      expect(s.sesion!.nombre, 'Dra. Uno');
      // El servidor tiene que conocer el aparato antes de aceptarle un lote.
      final alta = vistas.firstWhere((p) => p.url.path.endsWith('/dispositivos'));
      expect(jsonDecode(alta.body)['id'], s.dispositivoId);
      // Y la sesión se abre declarando el aparato, no en abstracto.
      final sesion = vistas.first;
      expect(jsonDecode(sesion.body)['dispositivo_id'], s.dispositivoId);
    });

    test('un error del servidor vuelve con su motivo, no como excepción',
        () async {
      final s = sync(
          responder: (p) => json({'detail': 'Usuario o contraseña incorrectos.'},
              401))
        ..configurar('https://servidor.ejemplo/api');

      final error = await s.entrar('dra.uno', 'mal');

      expect(error, 'Usuario o contraseña incorrectos.');
      expect(s.haySesion, isFalse);
    });

    test('sin servidor configurado no se pide credencial en balde', () async {
      final error = await sync().entrar('dra.uno', 'clave');

      expect(error, contains('dirección del servidor'));
      expect(vistas, isEmpty);
    });
  });

  group('enviar', () {
    test('lo aceptado deja de estar pendiente', () async {
      enrolar();
      final s = sync(
          responder: (p) => json({
                'lote_id': jsonDecode(p.body)['id'],
                'registros': 1,
                'aceptados': 1,
                'rechazados': 0,
                'detalle': const [],
                'ya_recibido': false,
              }))
        ..configurar('https://servidor.ejemplo/api');
      await s.entrar('dra.uno', 'clave');
      expect(s.pendientes, 1);

      await s.sincronizar();

      expect(s.pendientes, 0);
      expect(s.ultimo, isA<Hecho>());
      expect(s.rechazos, isEmpty);
    });

    test('lo rechazado queda a la vista, con el motivo del servidor', () async {
      final paciente = enrolar();
      final s = sync(
          responder: (p) => json({
                'lote_id': jsonDecode(p.body)['id'],
                'registros': 1,
                'aceptados': 0,
                'rechazados': 1,
                'detalle': [
                  {
                    'tipo': 'paciente',
                    'id': paciente.id,
                    'motivo': 'El centro HC no tiene aprobación del Comité de '
                        'Ética registrada.',
                  }
                ],
                'ya_recibido': false,
              }))
        ..configurar('https://servidor.ejemplo/api');
      await s.entrar('dra.uno', 'clave');

      await s.sincronizar();

      // Un rechazo sin motivo a la vista es un registro que se pierde sin que
      // nadie se entere.
      expect(s.rechazos.single.motivo, contains('Comité de Ética'));
      expect(s.pendientes, 1);
    });

    test('una respuesta con forma inesperada no revienta la app', () async {
      // Un proxy que devuelve su propia página, o una versión del servidor que
      // no cuadra. Lo que no puede pasar es que algo se dé por enviado.
      enrolar();
      final s = sync(responder: (_) => json(const {'algo': 'raro'}))
        ..configurar('https://servidor.ejemplo/api');
      await s.entrar('dra.uno', 'clave');

      final resultado = await s.sincronizar();

      expect(resultado, isA<Rechazado>());
      expect(s.pendientes, 1);
    });

    test('avisa mientras está en curso y deja de avisar al terminar', () async {
      enrolar();
      final s = sync(
          responder: (p) => json({
                'lote_id': jsonDecode(p.body)['id'],
                'registros': 1,
                'aceptados': 1,
                'rechazados': 0,
                'detalle': const [],
                'ya_recibido': false,
              }))
        ..configurar('https://servidor.ejemplo/api');
      await s.entrar('dra.uno', 'clave');

      final envio = s.sincronizar();
      expect(s.enCurso, isTrue);
      await envio;

      expect(s.enCurso, isFalse);
    });
  });
}
