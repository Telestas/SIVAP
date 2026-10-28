import 'package:flutter_test/flutter_test.dart';
import 'package:sivap/core/app_state.dart';
import 'package:sivap/data/local/almacen_local.dart';
import 'package:sivap/data/local/in_memory_study_repository.dart';
import 'package:sivap/data/local/seed_data.dart';
import 'package:sivap/data/remoto/autenticacion_firebase.dart';

void main() {
  test('el nombre del centro se actualiza sin cambiar su código', () {
    final perfil = {
      'institucion_codigo': 'centro-1',
      'institucion_nombre': 'Nombre anterior',
    };
    expect(AutenticacionFirebase.nombreVisibleCentro(perfil, null),
        'Nombre anterior');
    expect(
        AutenticacionFirebase.nombreVisibleCentro(
            perfil, {'nombre': 'Nombre actualizado de prueba'}),
        'Nombre actualizado de prueba');
    expect(perfil['institucion_codigo'], 'centro-1');
  });

  test('UNKNOWN muestra el detalle y permite restaurar solo un perfil cacheado',
      () {
    expect(
      AutenticacionFirebase.mensajeAutenticacion('UNKNOWN',
          detalle: 'No se pudo conectar con el servicio.'),
      contains('No se pudo conectar con el servicio.'),
    );
    expect(AutenticacionFirebase.errorPermiteCache('UNKNOWN'), isTrue);
    expect(
        AutenticacionFirebase.errorPermiteCache('permission-denied'), isFalse);
  });

  test('HTML 403 de Google se explica sin mostrar código HTML', () {
    final mensaje = AutenticacionFirebase.mensajeAutenticacion('UNKNOWN',
        detalle: 'Json conversion failed: <!DOCTYPE html><html>'
            '<title>Error 403 (Forbidden)</title>');
    expect(mensaje, contains('HTTP 403'));
    expect(mensaje, contains('VPN'));
    expect(mensaje, isNot(contains('<html>')));
  });

  test('el error de red web orienta ante el 403 observado en Cuba', () {
    final mensaje =
        AutenticacionFirebase.mensajeAutenticacion('network-request-failed');
    expect(mensaje, contains('HTTP 403'));
    expect(mensaje, contains('identitytoolkit.googleapis.com'));
    expect(mensaje, contains('VPN'));
  });

  test('el móvil toma el rol del perfil y vincula su base a una cuenta',
      () async {
    final repo = InMemoryStudyRepository();
    final estado = AppState(
      AlmacenLocal(
          repo: repo, persistente: true, cifrado: true, descripcion: 'Prueba'),
      autenticarUsuario: (usuario, clave) async => Seed.reclutador,
      cargarRepositorioRemoto: (_) async => repo,
    );

    await estado.iniciarSesionRemota('cuenta', 'clave');

    expect(estado.usuarioActual.id, Seed.reclutador.id);
    expect(estado.usuarioActual.roles, Seed.reclutador.roles);
    expect(repo.ajuste('propietario_uid'), Seed.reclutador.id);
    estado.dispose();
  });

  test('otra cuenta no puede abrir la base cifrada del primer usuario',
      () async {
    final repo = InMemoryStudyRepository();
    repo.guardarAjuste('propietario_uid', Seed.reclutador.id);
    var cerroSesion = false;
    final estado = AppState(
      AlmacenLocal(
          repo: repo, persistente: true, cifrado: true, descripcion: 'Prueba'),
      autenticarUsuario: (usuario, clave) async => Seed.aplicador,
      cargarRepositorioRemoto: (_) async => repo,
      cerrarSesionRemota: () async => cerroSesion = true,
    );

    await expectLater(
        estado.iniciarSesionRemota('otra', 'clave'), throwsStateError);
    expect(estado.usuario, isNull);
    expect(cerroSesion, isTrue);
    estado.dispose();
  });
}
