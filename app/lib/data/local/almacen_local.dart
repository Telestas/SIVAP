import '../../domain/repositories/study_repository.dart';

/// El almacén con el que arrancó la app, y qué garantías da de verdad.
///
/// Se lleva a la interfaz a propósito. Si por lo que sea la app termina
/// corriendo sin cifrado o sin persistencia —en el navegador, hoy— eso tiene
/// que verse en pantalla, no quedarse en un comentario del código. Un usuario
/// que cree que sus datos están cifrados cuando no lo están está peor que uno
/// que sabe que no lo están.
class AlmacenLocal {
  const AlmacenLocal({
    required this.repo,
    required this.persistente,
    required this.cifrado,
    required this.descripcion,
    this.advertencia,
  });

  final StudyRepository repo;

  /// Si los datos sobreviven al cierre de la app.
  final bool persistente;

  /// Si están cifrados en reposo.
  final bool cifrado;

  /// Para diagnóstico: "SQLite cifrado · /data/.../sivap_demo.db".
  final String descripcion;

  /// Texto a mostrar al usuario cuando el almacén no da las garantías que
  /// debería. `null` cuando todo está en orden.
  final String? advertencia;

  bool get aptoParaPacientesReales => persistente && cifrado;
}

/// Qué archivo de base de datos usa la app.
///
/// Demostración y producción son **archivos distintos**, no un modo dentro del
/// mismo archivo. Es la única forma de garantizar que un paciente inventado no
/// acabe nunca en el dataset del estudio.
enum ModoAlmacen {
  demostracion('sivap_demo.db'),
  produccion('sivap.db');

  const ModoAlmacen(this.archivo);
  final String archivo;
}
