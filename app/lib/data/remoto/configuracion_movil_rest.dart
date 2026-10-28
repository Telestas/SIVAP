import '../../domain/models/role.dart';
import '../../domain/repositories/study_repository.dart';
import '../local/sqlite_study_repository.dart';
import 'firebase_rest_movil.dart';

/// Refresca la configuración aprobada por Cloudflare y conserva la copia
/// cifrada previamente validada cuando la red no está disponible.
Future<StudyRepository> cargarConfiguracionMovilRest(StudyRepository repo,
    Investigador investigador, FirebaseRestMovil rest) async {
  if (repo is! SqliteStudyRepository || !repo.requiereTramos) return repo;
  try {
    final resultados = await Future.wait([
      rest.leer('instituciones/${investigador.institucion.codigo}'),
      rest.leer('estudios/livere'),
      rest.leer('estudios/livere/configuracion/consentimiento'),
    ]);
    final centro = resultados[0];
    final estudio = resultados[1];
    final consentimiento = resultados[2];
    repo.guardarAjuste('entrega_tramos',
        estudio?['entrega_tramos'] == 'reservas' ? 'reservas' : 'funcion');
    repo.guardarAjuste('configuracion_aprobada', '');
    if (centro != null && consentimiento != null) {
      repo.guardarConfiguracionAprobada(
        institucion: investigador.institucion,
        ceiAprobado: centro['cei_aprobado'] == true,
        consentimiento: consentimiento,
        pruebasIntegradas: estudio?['entorno'] == 'preproduccion' &&
            estudio?['captura_habilitada'] == true &&
            centro['habilitado_pruebas'] == true &&
            consentimiento['tipo'] == 'prueba' &&
            consentimiento['habilitado'] == true,
      );
    }
  } on FirebaseRestError catch (error) {
    if (error.estado != 0 && error.estado != 502 && error.estado != 503) {
      rethrow;
    }
  }
  return repo;
}
