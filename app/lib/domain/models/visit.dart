/// Estado de una visita dentro del calendario del estudio.
enum VisitStatus {
  programada('PROGRAMADA'),
  enCaptura('EN CAPTURA'),
  enviada('ENVIADO'),
  perdida('PERDIDA');

  const VisitStatus(this.etiqueta);
  final String etiqueta;

  /// Una vez enviada, no se sobrescribe: toda corrección pasa por auditoría
  /// (CLAUDE.md §2).
  bool get esInmutable => this == enviada || this == perdida;
}

/// Estado del registro frente al servidor central.
enum SyncStatus {
  local('Sin enviar'),
  enCola('En cola'),
  sincronizado('Enviado');

  const SyncStatus(this.etiqueta);
  final String etiqueta;
}

/// Registro de visita: los datos clínicos de un paciente en un día del estudio.
///
/// Entidad separada de [Patient] a propósito. No lleva nombre ni contacto:
/// solo [patientId]. Así el dataset clínico se exporta sin identidad.
class Visit {
  const Visit({
    required this.id,
    required this.patientId,
    required this.dia,
    required this.fechaProgramada,
    required this.status,
    required this.sync,
    required this.valores,
    required this.recolectorId,
    this.fechaCaptura,
    this.correcciones = 0,
  });

  final String id;
  final String patientId;

  /// Índice de visita (1, 3, 5, 10, 14…), no un número correlativo.
  final int dia;
  final DateTime fechaProgramada;
  final VisitStatus status;
  final SyncStatus sync;

  /// Valores capturados, indexados por `FieldDefinition.key`. Las claves las
  /// dicta la definición del formulario, no una estructura fija en el código.
  final Map<String, Object?> valores;

  final String recolectorId;
  final DateTime? fechaCaptura;

  /// Cuántas entradas de auditoría afectan a esta visita.
  final int correcciones;

  bool get vacia => valores.isEmpty;

  Visit copyWith({
    VisitStatus? status,
    SyncStatus? sync,
    Map<String, Object?>? valores,
    DateTime? fechaCaptura,
    int? correcciones,
  }) =>
      Visit(
        id: id,
        patientId: patientId,
        dia: dia,
        fechaProgramada: fechaProgramada,
        status: status ?? this.status,
        sync: sync ?? this.sync,
        valores: valores ?? this.valores,
        recolectorId: recolectorId,
        fechaCaptura: fechaCaptura ?? this.fechaCaptura,
        correcciones: correcciones ?? this.correcciones,
      );
}
