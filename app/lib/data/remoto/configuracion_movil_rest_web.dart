import '../../domain/models/role.dart';
import '../../domain/repositories/study_repository.dart';
import 'firebase_rest_movil.dart';

/// La configuración REST móvil solo se usa en Android.
Future<StudyRepository> cargarConfiguracionMovilRest(StudyRepository repo,
        Investigador investigador, FirebaseRestMovil rest) async =>
    repo;
