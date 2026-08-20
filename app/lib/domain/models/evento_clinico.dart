/// Fase del proceso de liberación de la VMI.
///
/// Sirve para agrupar los eventos en la línea de tiempo del paciente. No es un
/// calendario: una fase dura lo que la clínica determine, y un paciente puede
/// salir del proceso en cualquiera de ellas.
enum FaseEstudio {
  inclusion('Inclusión'),
  fase1('Fase 1 · Estratificación de riesgo'),
  fase2('Fase 2 · Cribado'),
  fase3('Fase 3 · Weaning y PVE'),
  extubacion('Extubación'),
  desenlaces('Desenlaces'),
  seguimiento('Seguimiento post-egreso');

  const FaseEstudio(this.etiqueta);
  final String etiqueta;

  /// Abreviatura para los indicadores compactos de las listas.
  String get abreviatura => switch (this) {
        FaseEstudio.inclusion => 'INC',
        FaseEstudio.fase1 => 'F1',
        FaseEstudio.fase2 => 'F2',
        FaseEstudio.fase3 => 'F3',
        FaseEstudio.extubacion => 'EXT',
        FaseEstudio.desenlaces => 'DES',
        FaseEstudio.seguimiento => 'SEG',
      };
}

/// Hito del proceso de liberación en el que se capturan datos.
///
/// **Restricción no negociable (CLAUDE.md §4).** Estos son los puntos de
/// captura del ensayo, y ocurren cuando la clínica lo determina — no en fechas
/// programadas. Algunos se repiten un número indeterminado de veces: el cribado
/// a diario hasta que el paciente cumple criterios, y la prueba de ventilación
/// espontánea de una a cuatro o más veces.
///
/// Añadir un hito que la práctica revele es añadir un valor aquí y su
/// definición de formulario. No hay refactor de por medio: esa es exactamente
/// la razón de no usar un índice de día.
enum TipoEvento {
  enrolamiento(
    etiqueta: 'Enrolamiento',
    fase: FaseEstudio.inclusion,
    cuando: 'Al cumplir criterios de inclusión',
  ),
  estratificacionRiesgo(
    etiqueta: 'Estratificación de riesgo',
    fase: FaseEstudio.fase1,
    cuando: 'Primeras 24 h de VMI',
  ),
  cribado(
    etiqueta: 'Cribado',
    fase: FaseEstudio.fase2,
    cuando: 'Desde las 24–48 h, a diario',
    repetible: true,
    sustantivoOcurrencia: 'día',
  ),
  evaluacionDiaria(
    etiqueta: 'Evaluación diaria',
    fase: FaseEstudio.fase3,
    cuando: 'Tras superar el cribado, a diario',
    repetible: true,
    sustantivoOcurrencia: 'día',
  ),
  pruebaVentilacionEspontanea(
    etiqueta: 'Prueba de ventilación espontánea',
    fase: FaseEstudio.fase3,
    cuando: 'Al concluir la evaluación diaria con éxito',
    repetible: true,
    sustantivoOcurrencia: 'intento',
  ),
  traqueostomia(
    etiqueta: 'Traqueostomía',
    fase: FaseEstudio.fase3,
    cuando: 'Si procede — cambia la trayectoria del paciente',
  ),
  extubacion(
    etiqueta: 'Extubación',
    fase: FaseEstudio.extubacion,
    cuando: 'Tras una PVE exitosa',
  ),
  soportePostExtubacion(
    etiqueta: 'Soporte post-extubación',
    fase: FaseEstudio.extubacion,
    cuando: 'Inmediato a la extubación',
  ),
  reintubacion(
    etiqueta: 'Reintubación',
    fase: FaseEstudio.desenlaces,
    cuando: 'Dentro de las 72 h posteriores a la extubación',
  ),
  egresoUci(
    etiqueta: 'Egreso de UCI',
    fase: FaseEstudio.desenlaces,
    cuando: 'Al alta de la unidad',
  ),
  seguimientoPostEgreso(
    etiqueta: 'Seguimiento post-egreso',
    fase: FaseEstudio.seguimiento,
    cuando: 'Hasta 28 días tras el egreso',
  );

  const TipoEvento({
    required this.etiqueta,
    required this.fase,
    required this.cuando,
    this.repetible = false,
    this.sustantivoOcurrencia = 'registro',
  });

  final String etiqueta;
  final FaseEstudio fase;

  /// Cuándo procede registrarlo. Se muestra en la línea de tiempo: el equipo no
  /// tiene por qué recordar el protocolo de memoria.
  final String cuando;

  /// Si admite más de una ocurrencia por paciente.
  final bool repetible;

  /// Cómo se nombra cada ocurrencia: "intento 2", "día 3".
  final String sustantivoOcurrencia;

  /// Los tipos de una fase, en el orden declarado.
  static List<TipoEvento> deFase(FaseEstudio fase) =>
      values.where((t) => t.fase == fase).toList();
}

/// Estado de un registro de evento.
///
/// No existe un estado "perdido": un evento que no ocurrió simplemente no tiene
/// registro (CLAUDE.md §4). Marcar ausencias exigiría saber de antemano qué
/// tenía que pasar, que es justo lo que un ensayo dirigido por eventos no sabe.
enum EstadoEvento {
  borrador('BORRADOR'),
  registrado('REGISTRADO');

  const EstadoEvento(this.etiqueta);
  final String etiqueta;

  /// Una vez registrado no se sobrescribe: toda corrección pasa por auditoría
  /// (CLAUDE.md §3).
  bool get esInmutable => this == registrado;
}

/// Estado del registro frente al servidor central.
enum SyncStatus {
  local('Sin enviar'),
  enCola('En cola'),
  sincronizado('Enviado');

  const SyncStatus(this.etiqueta);
  final String etiqueta;
}

/// Datos clínicos capturados en un hito del proceso de liberación.
///
/// Entidad separada de la ficha del paciente a propósito (CLAUDE.md §1). No
/// lleva nombre ni contacto: solo [patientId]. Así el dataset clínico se
/// exporta sin identidad.
class EventoClinico {
  const EventoClinico({
    required this.id,
    required this.patientId,
    required this.tipo,
    required this.ocurrencia,
    required this.fechaOcurrencia,
    required this.estado,
    required this.sync,
    required this.valores,
    required this.recolectorId,
    this.fechaCaptura,
    this.correcciones = 0,
  });

  final String id;
  final String patientId;
  final TipoEvento tipo;

  /// Número de ocurrencia dentro de su tipo, empezando en 1. Para los tipos no
  /// repetibles vale siempre 1.
  final int ocurrencia;

  /// Cuándo ocurrió **de verdad**, según lo declara quien captura. No hay fecha
  /// programada porque no hay calendario.
  final DateTime fechaOcurrencia;

  final EstadoEvento estado;
  final SyncStatus sync;

  /// Valores capturados, indexados por `FieldDefinition.key`. Las claves las
  /// dicta la definición del formulario, no una estructura fija en el código.
  final Map<String, Object?> valores;

  final String recolectorId;

  /// Cuándo se introdujo en el sistema, que puede ser bastante después de que
  /// ocurriera: se captura sin conexión, a veces al final del turno.
  final DateTime? fechaCaptura;

  /// Cuántas entradas de auditoría afectan a este registro.
  final int correcciones;

  bool get vacio => valores.isEmpty;

  /// "Prueba de ventilación espontánea · intento 2"
  String get referencia => tipo.repetible
      ? '${tipo.etiqueta} · ${tipo.sustantivoOcurrencia} $ocurrencia'
      : tipo.etiqueta;

  /// Referencia corta para el historial de auditoría: "PVE · intento 2".
  String get referenciaCorta =>
      tipo.repetible ? '${_siglas(tipo)} · $ocurrencia' : _siglas(tipo);

  static String _siglas(TipoEvento t) => switch (t) {
        TipoEvento.pruebaVentilacionEspontanea => 'PVE',
        TipoEvento.estratificacionRiesgo => 'Estratificación',
        TipoEvento.soportePostExtubacion => 'Soporte post-ext.',
        TipoEvento.seguimientoPostEgreso => 'Seguimiento',
        _ => t.etiqueta,
      };

  EventoClinico copyWith({
    EstadoEvento? estado,
    SyncStatus? sync,
    Map<String, Object?>? valores,
    DateTime? fechaOcurrencia,
    DateTime? fechaCaptura,
    int? correcciones,
  }) =>
      EventoClinico(
        id: id,
        patientId: patientId,
        tipo: tipo,
        ocurrencia: ocurrencia,
        fechaOcurrencia: fechaOcurrencia ?? this.fechaOcurrencia,
        estado: estado ?? this.estado,
        sync: sync ?? this.sync,
        valores: valores ?? this.valores,
        recolectorId: recolectorId,
        fechaCaptura: fechaCaptura ?? this.fechaCaptura,
        correcciones: correcciones ?? this.correcciones,
      );
}
