import 'package:cloud_firestore/cloud_firestore.dart';

import 'autenticacion_firebase.dart';
import '../../domain/models/role.dart';
import '../../domain/repositories/study_repository.dart';
import '../local/sqlite_study_repository.dart';

/// Refresca aprobación y texto real desde Firebase; sin red usa la copia
/// previamente validada y cifrada en el aparato.
Future<StudyRepository> cargarConfiguracionMovil(
    StudyRepository repo, Investigador investigador) async {
  if (repo is! SqliteStudyRepository || !repo.requiereTramos) return repo;
  try {
    final resultados = await Future.wait([
      FirebaseFirestore.instance
          .collection('instituciones')
          .doc(investigador.institucion.codigo)
          .get(const GetOptions(source: Source.server)),
      FirebaseFirestore.instance
          .collection('estudios')
          .doc('livere')
          .get(const GetOptions(source: Source.server)),
      FirebaseFirestore.instance
          .collection('estudios')
          .doc('livere')
          .collection('configuracion')
          .doc('consentimiento')
          .get(const GetOptions(source: Source.server)),
    ]);
    final centro = resultados[0].data();
    final estudio = resultados[1].data();
    final consentimiento = resultados[2].data();
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
  } on FirebaseException catch (error) {
    if (!AutenticacionFirebase.errorPermiteCache(error.code)) {
      rethrow;
    }
  }
  return repo;
}
