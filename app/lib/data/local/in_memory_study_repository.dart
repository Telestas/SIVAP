import '../../core/ids.dart';
import '../../domain/models/audit_entry.dart';
import '../../domain/models/consent.dart';
import '../../domain/models/evento_clinico.dart';
import '../../domain/models/institucion.dart';
import '../../domain/models/patient.dart';
import '../../domain/models/role.dart';
import '../../domain/repositories/study_repository.dart';
import '../allocation/allocation_strategy.dart';
import 'demo_dataset.dart';
import 'seed_data.dart';

/// Implementación en memoria, para pruebas y para el arranque en navegador.
///
/// El almacén de producción es SQLite cifrado (`SqliteStudyRepository`). Las
/// dos hablan la misma interfaz y muestran los mismos datos de demostración.
class InMemoryStudyRepository implements StudyRepository {
  InMemoryStudyRepository()
      : _allocation = SequentialAllocation(
          secuencia: Seed.secuenciaAleatorizacion,
          // Los pacientes de demostración ya consumieron sus posiciones.
          consumidas: Demo.pacientes.length,
        ) {
    _sembrar();
  }

  final AllocationStrategy _allocation;
  final Map<String, Patient> _pacientes = {};
  final Map<String, List<EventoClinico>> _eventos = {};
  final Map<String, Consent> _consentimientos = {};
  final List<AuditEntry> _auditoria = [];

  @override
  StudyConfig get config => Seed.config;

  // ── Lectura ────────────────────────────────────────────────────

  @override
  List<Patient> pacientes({String? recolectorId}) {
    final lista = _pacientes.values
        .where((p) => recolectorId == null || p.recolectorId == recolectorId)
        .toList();
    lista.sort((a, b) => a.codigo.compareTo(b.codigo));
    return lista;
  }

  @override
  Patient? paciente(String id) => _pacientes[id];

  @override
  List<EventoClinico> eventosDe(String patientId) {
    final lista = List<EventoClinico>.from(_eventos[patientId] ?? const []);
    lista.sort(_cronologico);
    return List.unmodifiable(lista);
  }

  /// Orden de la línea de tiempo: por fecha real, y a igualdad de fecha por el
  /// orden natural de las fases. Dos hitos del mismo día deben salir en el
  /// orden en que tienen sentido clínico, no en el que se teclearon.
  static int _cronologico(EventoClinico a, EventoClinico b) {
    final f = a.fechaOcurrencia.compareTo(b.fechaOcurrencia);
    if (f != 0) return f;
    final t = a.tipo.index.compareTo(b.tipo.index);
    return t != 0 ? t : a.ocurrencia.compareTo(b.ocurrencia);
  }

  @override
  EventoClinico? evento(String id) {
    for (final lista in _eventos.values) {
      for (final e in lista) {
        if (e.id == id) return e;
      }
    }
    return null;
  }

  @override
  EventoClinico? borradorAbierto(String patientId, TipoEvento tipo) {
    for (final e in _eventos[patientId] ?? const <EventoClinico>[]) {
      if (e.tipo == tipo && e.estado == EstadoEvento.borrador) return e;
    }
    return null;
  }

  @override
  List<AuditEntry> auditoria({String? entidadId, int? limite}) {
    final lista = _auditoria
        .where((a) => entidadId == null || a.entidadId == entidadId)
        .toList()
      ..sort((a, b) => b.ocurridoEn.compareTo(a.ocurridoEn));
    return limite == null ? lista : lista.take(limite).toList();
  }

  Iterable<EventoClinico> get _todos => _eventos.values.expand((e) => e);

  @override
  int get registrosEnCola =>
      _todos.where((e) => e.sync != SyncStatus.sincronizado && !e.vacio).length;

  @override
  int get dispositivosConCola => _todos
      .where((e) => e.sync != SyncStatus.sincronizado && !e.vacio)
      .map((e) => e.recolectorId)
      .toSet()
      .length;

  // ── Escritura ──────────────────────────────────────────────────

  @override
  Patient enrolar({
    required Investigador autor,
    required Institucion institucion,
    required String nombre,
    required String numeroHistoriaClinica,
    required String telefonoPrincipal,
    required int edad,
    required Sexo sexo,
    String? telefonoSecundario,
  }) {
    if (!autor.puedeEnrolar) {
      throw PermissionDenied(autor, 'enrolar pacientes');
    }
    // La rama la decide el módulo de aleatorización. El llamante no la propone
    // ni puede sugerirla: no hay parámetro para ello, a propósito.
    final asignacion = _allocation.asignar(ahora: DateTime.now());
    final paciente = Patient(
      id: Ids.nuevo('p'),
      codigo: _siguienteCodigo(institucion),
      nombre: nombre,
      numeroHistoriaClinica: numeroHistoriaClinica,
      telefonoPrincipal: telefonoPrincipal,
      telefonoSecundario: telefonoSecundario,
      institucion: institucion,
      edad: edad,
      sexo: sexo,
      protocolo: asignacion.protocolo,
      secuencia: asignacion.etiquetaSecuencia,
      posicionSecuencia: asignacion.posicion,
      asignadoEn: asignacion.asignadoEn,
      recolectorId: autor.id,
      enroladoEn: DateTime.now(),
    );
    _pacientes[paciente.id] = paciente;
    // Sin calendario que pre-crear: los eventos aparecen cuando ocurren
    // (CLAUDE.md §4).
    _eventos[paciente.id] = [];
    return paciente;
  }

  /// Correlativo por centro: «HC-004».
  ///
  /// Cuidado: sin conexión, dos dispositivos del mismo centro pueden emitir el
  /// mismo código hasta que sincronicen. Es molesto pero no corrompe nada, la
  /// clave real es el identificador aleatorio.
  String _siguienteCodigo(Institucion institucion) {
    final n = _pacientes.values
            .where((p) => p.institucion == institucion)
            .length +
        1;
    return '${institucion.codigo}-${n.toString().padLeft(3, '0')}';
  }

  @override
  Consent registrarConsentimiento({
    required Investigador autor,
    required String patientId,
    required List<List<({double x, double y})>> firmaTrazos,
  }) {
    if (!autor.puedeEnrolar) {
      throw PermissionDenied(autor, 'registrar consentimientos');
    }
    final doc = config.documentoConsentimiento;
    final consent = Consent(
      id: Ids.nuevo('c'),
      patientId: patientId,
      versionDocumento: doc.version,
      codigoCei: doc.codigoCei,
      firmadoEn: DateTime.now(),
      testigoId: autor.id,
      firmaTrazos: firmaTrazos,
    );
    _consentimientos[consent.id] = consent;
    _pacientes[patientId] =
        _pacientes[patientId]!.copyWith(consentimientoId: consent.id);
    return consent;
  }

  @override
  EventoClinico guardarBorrador({
    required Investigador autor,
    required String patientId,
    required TipoEvento tipo,
    required DateTime fechaOcurrencia,
    required Map<String, Object?> valores,
  }) =>
      _escribir(
        autor: autor,
        patientId: patientId,
        tipo: tipo,
        fechaOcurrencia: fechaOcurrencia,
        valores: valores,
        estado: EstadoEvento.borrador,
        sync: SyncStatus.local,
      );

  @override
  EventoClinico registrarEvento({
    required Investigador autor,
    required String patientId,
    required TipoEvento tipo,
    required DateTime fechaOcurrencia,
    required Map<String, Object?> valores,
  }) =>
      _escribir(
        autor: autor,
        patientId: patientId,
        tipo: tipo,
        fechaOcurrencia: fechaOcurrencia,
        valores: valores,
        estado: EstadoEvento.registrado,
        sync: SyncStatus.enCola,
      );

  EventoClinico _escribir({
    required Investigador autor,
    required String patientId,
    required TipoEvento tipo,
    required DateTime fechaOcurrencia,
    required Map<String, Object?> valores,
    required EstadoEvento estado,
    required SyncStatus sync,
  }) {
    _verificarPuedeCapturar(autor, patientId, tipo);

    final abierto = borradorAbierto(patientId, tipo);
    final lista = _eventos[patientId]!;

    if (abierto != null) {
      final actualizado = abierto.copyWith(
        estado: estado,
        sync: sync,
        valores: Map.unmodifiable(valores),
        fechaOcurrencia: fechaOcurrencia,
        fechaCaptura: DateTime.now(),
      );
      lista[lista.indexWhere((e) => e.id == abierto.id)] = actualizado;
      return actualizado;
    }

    final nuevo = EventoClinico(
      id: Ids.nuevo('e'),
      patientId: patientId,
      tipo: tipo,
      ocurrencia: _siguienteOcurrencia(patientId, tipo),
      fechaOcurrencia: fechaOcurrencia,
      estado: estado,
      sync: sync,
      valores: Map.unmodifiable(valores),
      recolectorId: autor.id,
      institucion: autor.institucion,
      fechaCaptura: DateTime.now(),
    );
    lista.add(nuevo);
    return nuevo;
  }

  void _verificarPuedeCapturar(
      Investigador autor, String patientId, TipoEvento tipo) {
    // No es un permiso administrativo: es la separación de funciones que el
    // cegamiento exige (BASES §4).
    if (!autor.puedeCapturar(tipo)) throw FueraDeSuFuncion(autor, tipo);

    final p = _pacientes[patientId]!;
    if (!p.tieneConsentimiento) {
      throw StateError(
          'No se pueden capturar eventos de ${p.codigo} sin consentimiento '
          'registrado.');
    }
    // Un hito no repetible que ya se registró no se duplica: se corrige, y la
    // corrección deja rastro (CLAUDE.md §3).
    if (!tipo.repetible &&
        (_eventos[patientId] ?? const <EventoClinico>[])
            .any((e) => e.tipo == tipo && e.estado.esInmutable)) {
      throw EventoNoRepetible(tipo);
    }
  }

  int _siguienteOcurrencia(String patientId, TipoEvento tipo) =>
      (_eventos[patientId] ?? const <EventoClinico>[])
          .where((e) => e.tipo == tipo)
          .length +
      1;

  @override
  EventoClinico corregirEventoRegistrado({
    required Investigador autor,
    required String eventoId,
    required String campo,
    required Object? valorNuevo,
    required String motivo,
  }) {
    if (!autor.puedeCorregirRegistrado) {
      throw PermissionDenied(autor, 'corregir registros ya enviados');
    }
    if (motivo.trim().isEmpty) {
      throw ArgumentError.value(motivo, 'motivo',
          'Una corrección sin motivo es una edición silenciosa: no se admite.');
    }
    final actual = evento(eventoId)!;
    final paciente = _pacientes[actual.patientId]!;
    final anterior = actual.valores[campo];

    final corregido = actual.copyWith(
      valores: Map.unmodifiable({...actual.valores, campo: valorNuevo}),
      // Vuelve a la cola: el servidor debe recibir la versión corregida junto
      // con su entrada de auditoría.
      sync: SyncStatus.enCola,
      correcciones: actual.correcciones + 1,
    );
    final lista = _eventos[actual.patientId]!;
    lista[lista.indexWhere((e) => e.id == eventoId)] = corregido;

    _auditoria.add(AuditEntry(
      id: Ids.nuevo('a'),
      ocurridoEn: DateTime.now(),
      autorId: autor.id,
      autorNombre: autor.nombre,
      entidad: AuditEntity.evento,
      entidadId: eventoId,
      // El código del paciente, no su nombre: la auditoría es parte del
      // dataset clínico (CLAUDE.md §1).
      descripcionObjetivo: '${paciente.codigo} · ${actual.referenciaCorta}',
      campo: campo,
      valorAnterior: anterior?.toString(),
      valorNuevo: valorNuevo?.toString(),
      motivo: motivo.trim(),
    ));
    return corregido;
  }

  // ── Siembra de datos de demostración ───────────────────────────

  void _sembrar() {
    for (final d in Demo.pacientes) {
      _pacientes[d.id] = Patient(
        id: d.id,
        codigo: d.codigo,
        nombre: d.nombre,
        numeroHistoriaClinica: d.hc,
        telefonoPrincipal: d.telefono,
        institucion: d.institucion,
        edad: d.edad,
        sexo: d.sexo,
        protocolo: d.protocolo,
        secuencia: Seed.secuenciaAleatorizacion.etiqueta,
        posicionSecuencia: Demo.pacientes.indexOf(d) + 1,
        asignadoEn: d.enroladoEn,
        recolectorId: d.recolectorId,
        enroladoEn: d.enroladoEn,
        consentimientoId: 'c-demo-${d.id}',
      );

      final porTipo = <TipoEvento, int>{};
      _eventos[d.id] = [
        for (final ev in d.eventos)
          () {
            final ocurrencia = (porTipo[ev.tipo] = (porTipo[ev.tipo] ?? 0) + 1);
            final fecha =
                d.enroladoEn.add(Duration(days: ev.diaDesdeEnrolamiento));
            final autor = Seed.porId(ev.recolectorId ?? d.recolectorId);
            return EventoClinico(
              id: idEventoDemo(d.id, ev.tipo, ocurrencia),
              patientId: d.id,
              tipo: ev.tipo,
              ocurrencia: ocurrencia,
              fechaOcurrencia: fecha,
              estado:
                  ev.borrador ? EstadoEvento.borrador : EstadoEvento.registrado,
              sync: ev.borrador ? SyncStatus.local : d.sync,
              valores: ev.valores,
              recolectorId: autor.id,
              institucion: d.institucion,
              fechaCaptura: DateTime(fecha.year, fecha.month, fecha.day, 9, 30),
            );
          }()
      ];
    }

    for (final a in Demo.auditoria) {
      _auditoria.add(AuditEntry(
        id: Ids.nuevo('a'),
        ocurridoEn: a.ocurridoEn,
        autorId: a.autor.id,
        autorNombre: a.autor.nombre,
        entidad: AuditEntity.evento,
        entidadId: idEventoDemo(a.pacienteId, a.tipo, a.ocurrencia),
        descripcionObjetivo:
            '${Demo.porId(a.pacienteId).codigo} · ${a.tipo.etiqueta}',
        campo: a.campo,
        valorAnterior: a.valorAnterior,
        valorNuevo: a.valorNuevo,
        motivo: a.motivo,
      ));
    }
  }

  /// Identificador estable de un evento de demostración, para que las entradas
  /// de auditoría sembradas apunten al evento correcto.
  static String idEventoDemo(
          String pacienteId, TipoEvento tipo, int ocurrencia) =>
      'e-$pacienteId-${tipo.name}-$ocurrencia';
}
