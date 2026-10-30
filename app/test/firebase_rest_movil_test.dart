import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sivap/data/remoto/cliente_firebase_rest.dart';
import 'package:sivap/data/remoto/cliente_tramos_rest.dart';
import 'package:sivap/data/remoto/autenticacion_rest_movil.dart';
import 'package:sivap/data/remoto/autenticacion_firebase.dart';
import 'package:sivap/data/remoto/diagnostico_red_io.dart';
import 'package:sivap/data/remoto/firebase_rest_movil.dart';
import 'package:sivap/data/remoto/lote.dart';
import 'package:sivap/domain/models/role.dart';

class _AlmacenFalso implements AlmacenSesion {
  final datos = <String, String>{};

  @override
  Future<void> borrar(String clave) async => datos.remove(clave);

  @override
  Future<void> escribir(String clave, String valor) async =>
      datos[clave] = valor;

  @override
  Future<String?> leer(String clave) async => datos[clave];
}

class _RestFalso extends FirebaseRestMovil {
  _RestFalso(this.documentos);

  final Map<String, Map<String, dynamic>?> documentos;
  List<Map<String, Object?>>? escrituras;
  String? transaccionEnCommit;

  @override
  bool get haySesion => true;

  @override
  Future<String> comenzarTransaccion() async => 'transaccion-de-prueba';

  @override
  Future<Map<String, Map<String, dynamic>?>> leerTransaccion(
      String transaccion, List<String> rutas) async {
    expect(transaccion, 'transaccion-de-prueba');
    return documentos;
  }

  @override
  Future<void> commit(List<Map<String, Object?>> lote,
      {String? transaccion}) async {
    escrituras = lote;
    transaccionEnCommit = transaccion;
  }
}

class _RestSolicitudFalso extends FirebaseRestMovil {
  bool verificada = false;
  int correos = 0;
  Map<String, Object?>? solicitud;

  @override
  String? get uid => 'uid-prueba';

  @override
  Future<void> entrar(String correo, String contrasena) async {}

  @override
  Future<Map<String, dynamic>> datosCuenta() async => {
        'email': 'persona@example.org',
        'emailVerified': verificada,
      };

  @override
  Future<Map<String, dynamic>?> leer(String ruta) async =>
      ruta.startsWith('solicitudes_acceso/') ? solicitud : null;

  @override
  Future<void> enviarCorreoVerificacion() async {
    correos++;
  }

  @override
  Future<void> escribir(String ruta, Map<String, Object?> datos,
      {bool crear = false,
      bool marcaTiempo = false,
      bool fusionar = false}) async {
    solicitud = {...?solicitud, ...datos};
  }

  @override
  Future<void> salir() async {}
}

void main() {
  const prefijo = 'projects/sivap-f5060/databases/(default)/documents/';

  test('una sola solicitud espera verificación y se promueve sin reenviar',
      () async {
    final rest = _RestSolicitudFalso();
    final acceso = AutenticacionRestMovil(rest);
    await expectLater(
      acceso.solicitarAcceso(
          'persona@example.org', 'clave-prueba', 'Persona', 'C01'),
      throwsA(isA<VerificacionPendiente>()),
    );
    expect(rest.solicitud?['estado'], 'pendiente_verificacion');
    expect(rest.correos, 1);
    rest.verificada = true;
    await acceso.solicitarAcceso(
        'persona@example.org', 'clave-prueba', 'Persona', 'C01');
    expect(rest.solicitud?['estado'], 'pendiente');
    expect(rest.correos, 1);
  });

  test('Firestore REST conserva tipos, listas y mapas', () {
    final codificado = FirebaseRestMovil.camposDocumento({
      'edad': 62,
      'activo': true,
      'nombre': 'Prueba',
      'valores': [
        1,
        null,
        {'x': 0.5}
      ],
    });
    expect(FirebaseRestMovil.valoresDocumento({'fields': codificado}), {
      'edad': 62,
      'activo': true,
      'nombre': 'Prueba',
      'valores': [
        1,
        null,
        {'x': 0.5}
      ],
    });
  });

  test('respuestas de consultas aceptan arreglo y flujo JSON', () {
    expect(FirebaseRestMovil.decodificarFlujo('[{"found":{"name":"a"}}]'),
        hasLength(1));
    expect(
        FirebaseRestMovil.decodificarFlujo(
            '{"found":{"name":"a"}}\n{"missing":"b"}\n'),
        hasLength(2));
  });

  test('inicio de sesión y perfil usan solo el origen Cloudflare', () async {
    final rutas = <String>[];
    final almacen = _AlmacenFalso();
    final cliente = MockClient((peticion) async {
      expect(peticion.url.host, 'sivap.pages.dev');
      rutas.add(peticion.url.path);
      if (peticion.url.path.endsWith('signInWithPassword')) {
        return http.Response(
            jsonEncode({
              'idToken': 'id-token',
              'refreshToken': 'refresh-token',
              'localId': 'uid',
              'email': 'persona@example.org',
              'expiresIn': '3600',
            }),
            200,
            headers: {'content-type': 'application/json'});
      }
      expect(peticion.headers['authorization'], 'Bearer id-token');
      return http.Response(
          jsonEncode({
            'fields': {
              'nombre': {'stringValue': 'Centro de prueba'}
            }
          }),
          200,
          headers: {'content-type': 'application/json'});
    });
    final rest = FirebaseRestMovil(cliente: cliente, almacen: almacen);
    await rest.entrar('persona@example.org', 'secreto-de-prueba');
    expect(await rest.leer('instituciones/Hospital-1'),
        {'nombre': 'Centro de prueba'});
    expect(almacen.datos['sivap.firebase.refresh.v1'], 'refresh-token');
    expect(rutas, [
      '/api/firebase/auth/v1/accounts:signInWithPassword',
      '/v1/projects/sivap-f5060/databases/(default)/documents/instituciones/Hospital-1',
    ]);
  });

  test('el perfil aprobado conserva rol y centro tras el acceso REST',
      () async {
    final cliente = MockClient((peticion) async {
      expect(peticion.url.host, 'sivap.pages.dev');
      final ruta = peticion.url.path;
      if (ruta.endsWith('signInWithPassword')) {
        return http.Response(
            jsonEncode({
              'idToken': 'id-token',
              'refreshToken': 'refresh-token',
              'localId': 'uid',
              'email': 'persona@example.org',
              'expiresIn': '3600',
            }),
            200,
            headers: {'content-type': 'application/json'});
      }
      if (ruta.endsWith('solicitudes_acceso/uid')) {
        return http.Response(
            jsonEncode({'error': {'status': 'NOT_FOUND'}}), 404,
            headers: {'content-type': 'application/json'});
      }
      if (ruta.endsWith('investigadores/uid')) {
        return http.Response(
            jsonEncode({
              'fields': FirebaseRestMovil.camposDocumento({
                'nombre': 'Persona de prueba',
                'roles': ['reclutador'],
                'institucion_codigo': 'Hospital-1',
              }),
            }),
            200,
            headers: {'content-type': 'application/json'});
      }
      if (ruta.endsWith('instituciones/Hospital-1')) {
        return http.Response(
            jsonEncode({
              'fields': FirebaseRestMovil.camposDocumento(
                  {'nombre': 'Hospital de prueba'}),
            }),
            200,
            headers: {'content-type': 'application/json'});
      }
      if (ruta.endsWith('accounts:lookup')) {
        return http.Response(
            jsonEncode({
              'users': [
                {'email': 'persona@example.org', 'emailVerified': true}
              ]
            }),
            200,
            headers: {'content-type': 'application/json'});
      }
      fail('Ruta inesperada: $ruta');
    });
    final rest = FirebaseRestMovil(cliente: cliente, almacen: _AlmacenFalso());
    final usuario = await AutenticacionRestMovil(rest)
        .entrar('persona@example.org', 'clave-de-prueba');
    expect(usuario.id, 'uid');
    expect(usuario.roles, {Rol.reclutador});
    expect(usuario.institucion.codigo, 'Hospital-1');
    expect(usuario.institucion.nombre, 'Hospital de prueba');
  });

  test('403 HTML no se muestra como respuesta de Firebase', () async {
    final rest = FirebaseRestMovil(
      cliente: MockClient((_) async => http.Response('<html>403</html>', 403,
          headers: {'content-type': 'text/html'})),
      almacen: _AlmacenFalso(),
    );
    await expectLater(
        rest.entrar('a@b.c', 'clave'),
        throwsA(isA<FirebaseRestError>()
            .having((e) => e.mensaje, 'mensaje', contains('HTTP 403'))));
  });

  test('un fallo de DNS se distingue de un fallo de contraseña', () {
    expect(diagnosticoConexion(const SocketException('Failed host lookup')),
        contains('DNS'));
  });

  test('renovación de sesión usa el proxy y conserva el token nuevo', () async {
    final almacen = _AlmacenFalso();
    await almacen.escribir('sivap.firebase.refresh.v1', 'refresh-anterior');
    final cliente = MockClient((peticion) async {
      expect(peticion.url.host, 'sivap.pages.dev');
      expect(peticion.url.path, '/api/firebase/token/v1/token');
      expect(peticion.bodyFields['grant_type'], 'refresh_token');
      expect(peticion.bodyFields['refresh_token'], 'refresh-anterior');
      return http.Response(
          jsonEncode({
            'id_token': 'id-renovado',
            'refresh_token': 'refresh-nuevo',
            'user_id': 'uid',
            'expires_in': '3600',
          }),
          200,
          headers: {'content-type': 'application/json'});
    });
    final rest = FirebaseRestMovil(cliente: cliente, almacen: almacen);
    await rest.restaurarToken();
    expect(await rest.idToken(), 'id-renovado');
    expect(rest.uid, 'uid');
    expect(almacen.datos['sivap.firebase.refresh.v1'], 'refresh-nuevo');
  });

  test('una transacción abortada se repite completa', () async {
    final rest = _RestFalso({});
    var intentos = 0;
    final resultado = await rest.reintentarTransaccion(() async {
      intentos++;
      if (intentos == 1) {
        throw const FirebaseRestError(409, 'Conflicto', codigo: 'ABORTED');
      }
      return 'confirmado';
    });
    expect(resultado, 'confirmado');
    expect(intentos, 2);
  });

  test('tramo y reserva se confirman en la misma transacción', () async {
    final tramo = {
      'desde': 1,
      'hasta': 3,
      'codigo_binario': '01',
      'consumidas': 0,
      'asignado_en': '2026-01-01T00:00:00Z',
      'autor_uid': 'uid',
      'institucion_codigo': 'Hospital-1',
    };
    final rest = _RestFalso({
      '${prefijo}reservas_tramos/uid': {
        'tramo': tramo,
        'dispositivo_id': null,
      },
      '${prefijo}tramos/aparato': null,
    });
    expect(await ClienteTramosRest(rest).recoger('uid', 'aparato'), tramo);
    expect(rest.transaccionEnCommit, 'transaccion-de-prueba');
    expect(rest.escrituras, hasLength(2));
    expect((rest.escrituras![0]['currentDocument'] as Map)['exists'], false);
    expect((rest.escrituras![1]['updateMask'] as Map)['fieldPaths'],
        ['dispositivo_id']);
  });

  test('registro de aparato fusiona campos y usa hora del servidor', () async {
    final rest = _RestFalso({});
    await rest.escribir(
        'dispositivos/aparato',
        {
          'autor_uid': 'uid',
          'institucion_codigo': 'Hospital-1',
          'registrado_en': null,
        },
        marcaTiempo: true,
        fusionar: true);
    final escritura = rest.escrituras!.single;
    expect((escritura['updateMask'] as Map)['fieldPaths'],
        ['autor_uid', 'institucion_codigo']);
    expect((escritura['updateTransforms'] as List).single,
        {'fieldPath': 'registrado_en', 'setToServerValue': 'REQUEST_TIME'});
  });

  test('aprobación crea perfil y actualiza solicitud en un commit', () async {
    final rest = _RestFalso({});
    await rest.aprobarSolicitud(
        const SolicitudRest('uid', {
          'nombre': 'Persona de prueba',
          'correo': 'persona@example.org',
          'institucion_codigo': 'Hospital-1',
          'estado': 'pendiente',
        }),
        'reclutador',
        'Hospital-1',
        'principal');
    expect(rest.escrituras, hasLength(2));
    expect((rest.escrituras![0]['currentDocument'] as Map)['exists'], false);
    for (final escritura in rest.escrituras!) {
      expect((escritura['updateTransforms'] as List).single,
          {'fieldPath': 'aprobado_en', 'setToServerValue': 'REQUEST_TIME'});
    }
  });

  test('tramo ya reclamado por otro aparato no se reasigna', () async {
    final rest = _RestFalso({
      '${prefijo}reservas_tramos/uid': {
        'tramo': {'desde': 1},
        'dispositivo_id': 'otro',
      },
      '${prefijo}tramos/aparato': null,
    });
    await expectLater(
        ClienteTramosRest(rest).recoger('uid', 'aparato'), throwsStateError);
    expect(rest.escrituras, isNull);
  });

  test('acuse previo impide duplicar el lote', () async {
    final rest = _RestFalso({
      '${prefijo}lotes/lote-1': {'aceptados': 0},
    });
    final cliente = ClienteFirebaseRest(
      rest: rest,
      investigadorId: 'uid',
      institucionCodigo: 'Hospital-1',
      roles: {Rol.reclutador},
    );
    final resultado =
        await cliente.enviar(Lote(id: 'lote-1', dispositivoId: 'aparato'));
    expect(resultado.yaRecibido, isTrue);
    expect(rest.escrituras, isNull);
  });

  test('acuse nuevo se escribe con tiempo del servidor', () async {
    final rest = _RestFalso({'${prefijo}lotes/lote-1': null});
    final cliente = ClienteFirebaseRest(
      rest: rest,
      investigadorId: 'uid',
      institucionCodigo: 'Hospital-1',
      roles: {Rol.reclutador},
    );
    final resultado =
        await cliente.enviar(Lote(id: 'lote-1', dispositivoId: 'aparato'));
    expect(resultado.yaRecibido, isFalse);
    expect(rest.escrituras, hasLength(1));
    expect(rest.transaccionEnCommit, 'transaccion-de-prueba');
    expect((rest.escrituras!.single['updateTransforms'] as List).single,
        {'fieldPath': 'sincronizado_en', 'setToServerValue': 'REQUEST_TIME'});
  });
}
