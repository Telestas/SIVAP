import '../../domain/models/audit_entry.dart';
import '../../domain/models/consent.dart';
import '../../domain/models/patient.dart';
import '../../domain/models/protocolo.dart';
import '../../domain/models/role.dart';
import '../../domain/models/visit.dart';
import '../../domain/repositories/study_repository.dart';
import '../allocation/allocation_strategy.dart';
import 'demo_dataset.dart';
import 'seed_data.dart';

/// Implementación en memoria del Hito 1.
///
/// Sustituible por SQLite cifrado (Drift/Isar) + cola de sincronización sin
/// tocar ni una pantalla: todas hablan con [StudyRepository].
///
/// PENDIENTE de hitos posteriores: cifrado en reposo y envío al servidor. Este
/// almacén es volátil y no debe usarse con pacientes reales.
class InMemoryStudyRepository implements StudyRepository {
  InMemoryStudyRepository()
      : _allocation = SequentialAllocation(
          secuencia: Seed.secuenciaAleatorizacion,
          // Las 7 primeras entradas ya las consumieron los pacientes de prueba.
          consumidas: 7,
        ) {
    _sembrar();
  }

  final AllocationStrategy _allocation;
  final Map<String, Patient> _pacientes = {};
  final Map<String, List<Visit>> _visitas = {};
  final Map<String, Consent> _consentimientos = {};
  final List<AuditEntry> _auditoria = [];
  int _secuenciaId = 0;

  String _nuevoId(String prefijo) => '$prefijo-${(++_secuenciaId).toString().padLeft(4, '0')}';

  @override
  StudyConfig get config => Seed.config;

  // ── Lectura ────────────────────────────────────────────────────

  @override
  List<Patient> pacientes({String? recolectorId}) {
    final lista = _pacientes.values
        .where((p) => recolectorId == null || p.recolectorId == recolectorId)
        .toList();
    lista.sort((a, b) => a.nombre.compareTo(b.nombre));
    return lista;
  }

  @override
  Patient? paciente(String id) => _pacientes[id];

  @override
  List<Visit> visitasDe(String patientId) =>
      List.unmodifiable(_visitas[patientId] ?? const []);

  @override
  Visit? visita(String patientId, int dia) {
    for (final v in _visitas[patientId] ?? const <Visit>[]) {
      if (v.dia == dia) return v;
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

  @override
  int get registrosEnCola => _visitas.values
      .expand((v) => v)
      .where((v) => v.sync != SyncStatus.sincronizado && !v.vacia)
      .length;

  @override
  int get dispositivosConCola => _visitas.values
      .expand((v) => v)
      .where((v) => v.sync != SyncStatus.sincronizado && !v.vacia)
      .map((v) => v.recolectorId)
      .toSet()
      .length;

  // ── Escritura ──────────────────────────────────────────────────

  @override
  Patient enrolar({
    required Investigador autor,
    required String nombre,
    required String carneIdentidad,
    required int edad,
    required Sexo sexo,
    required String numeroHistoriaClinica,
    required String telefono,
    required String direccion,
  }) {
    if (!autor.role.puedeEnrolar) {
      throw PermissionDenied(autor.role, 'enrolar pacientes');
    }
    // La rama la decide el módulo de aleatorización. El llamante no la propone
    // ni puede sugerirla: no hay parámetro para ello, a propósito.
    final asignacion = _allocation.asignar(ahora: DateTime.now());
    final paciente = Patient(
      id: _nuevoId('p'),
      nombre: nombre,
      carneIdentidad: carneIdentidad,
      edad: edad,
      sexo: sexo,
      numeroHistoriaClinica: numeroHistoriaClinica,
      telefono: telefono,
      direccion: direccion,
      protocolo: asignacion.protocolo,
      bloqueAleatorizacion: asignacion.etiquetaSecuencia,
      asignadoEn: asignacion.asignadoEn,
      recolectorId: autor.id,
      enroladoEn: DateTime.now(),
    );
    _pacientes[paciente.id] = paciente;
    _visitas[paciente.id] = _calendarioVacio(paciente);
    return paciente;
  }

  @override
  Consent registrarConsentimiento({
    required Investigador autor,
    required String patientId,
    required List<List<({double x, double y})>> firmaTrazos,
  }) {
    if (!autor.role.puedeEnrolar) {
      throw PermissionDenied(autor.role, 'registrar consentimientos');
    }
    final doc = config.documentoConsentimiento;
    final consent = Consent(
      id: _nuevoId('c'),
      patientId: patientId,
      versionDocumento: doc.version,
      codigoCei: doc.codigoCei,
      firmadoEn: DateTime.now(),
      testigoId: autor.id,
      firmaTrazos: firmaTrazos,
    );
    _consentimientos[consent.id] = consent;
    _pacientes[patientId] = _pacientes[patientId]!.copyWith(consentimientoId: consent.id);
    return consent;
  }

  @override
  Visit guardarBorrador({
    required Investigador autor,
    required String patientId,
    required int dia,
    required Map<String, Object?> valores,
  }) =>
      _escribirVisita(
        autor: autor,
        patientId: patientId,
        dia: dia,
        valores: valores,
        status: VisitStatus.enCaptura,
        sync: SyncStatus.local,
      );

  @override
  Visit cerrarVisita({
    required Investigador autor,
    required String patientId,
    required int dia,
    required Map<String, Object?> valores,
  }) =>
      _escribirVisita(
        autor: autor,
        patientId: patientId,
        dia: dia,
        valores: valores,
        status: VisitStatus.enviada,
        sync: SyncStatus.enCola,
      );

  Visit _escribirVisita({
    required Investigador autor,
    required String patientId,
    required int dia,
    required Map<String, Object?> valores,
    required VisitStatus status,
    required SyncStatus sync,
  }) {
    if (!autor.role.puedeCapturarVisitas) {
      throw PermissionDenied(autor.role, 'capturar visitas');
    }
    final paciente = _pacientes[patientId]!;
    if (!paciente.tieneConsentimiento) {
      throw StateError(
          'No se pueden capturar visitas de ${paciente.nombre} sin consentimiento registrado.');
    }
    final actual = visita(patientId, dia)!;
    // Restricción CLAUDE.md §2: lo ya enviado no se sobrescribe por esta vía.
    if (actual.status.esInmutable) throw SilentEditRejected(actual.id);

    final nueva = actual.copyWith(
      status: status,
      sync: sync,
      valores: Map.unmodifiable(valores),
      fechaCaptura: DateTime.now(),
    );
    _reemplazar(patientId, nueva);
    return nueva;
  }

  @override
  Visit corregirVisitaEnviada({
    required Investigador autor,
    required String patientId,
    required int dia,
    required String campo,
    required Object? valorNuevo,
    required String motivo,
  }) {
    if (!autor.role.puedeCorregirEnviado) {
      throw PermissionDenied(autor.role, 'corregir registros ya enviados');
    }
    if (motivo.trim().isEmpty) {
      throw ArgumentError.value(motivo, 'motivo',
          'Una corrección sin motivo es una edición silenciosa: no se admite.');
    }
    final actual = visita(patientId, dia)!;
    final paciente = _pacientes[patientId]!;
    final anterior = actual.valores[campo];

    final nueva = actual.copyWith(
      valores: Map.unmodifiable({...actual.valores, campo: valorNuevo}),
      // Corregir devuelve el registro a la cola: el servidor debe recibir la
      // versión corregida junto con su entrada de auditoría.
      sync: SyncStatus.enCola,
      correcciones: actual.correcciones + 1,
    );
    _reemplazar(patientId, nueva);

    _auditoria.add(AuditEntry(
      id: _nuevoId('a'),
      ocurridoEn: DateTime.now(),
      autorId: autor.id,
      autorNombre: autor.nombre,
      entidad: AuditEntity.visita,
      entidadId: actual.id,
      descripcionObjetivo: '${paciente.apellidos} · D$dia',
      campo: campo,
      valorAnterior: anterior?.toString(),
      valorNuevo: valorNuevo?.toString(),
      motivo: motivo.trim(),
    ));
    return nueva;
  }

  void _reemplazar(String patientId, Visit visita) {
    final lista = _visitas[patientId]!;
    lista[lista.indexWhere((v) => v.dia == visita.dia)] = visita;
  }

  List<Visit> _calendarioVacio(Patient p) => [
        for (final dia in config.definicionFormulario.diasVisita)
          Visit(
            id: _nuevoId('v'),
            patientId: p.id,
            dia: dia,
            // Día 1 el día del enrolamiento; el resto, a los N-1 días.
            fechaProgramada: DateTime(
                p.enroladoEn.year, p.enroladoEn.month, p.enroladoEn.day + dia - 1),
            status: VisitStatus.programada,
            sync: SyncStatus.local,
            valores: const {},
            recolectorId: p.recolectorId,
          )
      ];

  // ── Siembra de datos de demostración ───────────────────────────

  void _sembrar() {
    final dias = config.definicionFormulario.diasVisita;

    for (final d in Demo.pacientes) {
      _pacientes[d.id] = Patient(
        id: d.id,
        nombre: d.nombre,
        carneIdentidad: d.carneIdentidad,
        edad: d.edad,
        sexo: d.sexo,
        numeroHistoriaClinica: d.hc,
        telefono: d.telefono,
        direccion: d.direccion,
        protocolo: d.protocolo,
        bloqueAleatorizacion: Seed.secuenciaAleatorizacion.etiqueta,
        asignadoEn: d.enroladoEn,
        recolectorId: d.recolectorId,
        enroladoEn: d.enroladoEn,
        consentimientoId: 'c-demo-${d.id}',
      );

      _visitas[d.id] = [
        for (var i = 0; i < dias.length; i++)
          Visit(
            id: idVisitaDemo(d.id, dias[i]),
            patientId: d.id,
            dia: dias[i],
            fechaProgramada: DateTime(d.enroladoEn.year, d.enroladoEn.month,
                d.enroladoEn.day + dias[i] - 1),
            status: d.estados[i],
            sync: d.estados[i] == VisitStatus.enviada
                ? d.sync
                : SyncStatus.local,
            valores: d.estados[i] == VisitStatus.programada
                ? const {}
                : Demo.valores(i),
            recolectorId: d.recolectorId,
            fechaCaptura: d.estados[i] == VisitStatus.programada
                ? null
                : DateTime(d.enroladoEn.year, d.enroladoEn.month,
                    d.enroladoEn.day + dias[i] - 1, 9, 30),
          )
      ];
    }

    for (final a in Demo.auditoria) {
      _auditoria.add(AuditEntry(
        id: _nuevoId('a'),
        ocurridoEn: a.ocurridoEn,
        autorId: a.autor.id,
        autorNombre: a.autor.nombre,
        entidad: a.entidad,
        entidadId: a.dia == null
            ? a.pacienteId
            : idVisitaDemo(a.pacienteId, a.dia!),
        descripcionObjetivo: a.descripcionObjetivo,
        campo: a.campo,
        valorAnterior: a.valorAnterior,
        valorNuevo: a.valorNuevo,
        motivo: a.motivo,
      ));
    }
  }

  /// Identificador estable de una visita de demostración, para que las
  /// entradas de auditoría sembradas apunten a la visita correcta.
  static String idVisitaDemo(String pacienteId, int dia) =>
      'v-$pacienteId-$dia';
}
