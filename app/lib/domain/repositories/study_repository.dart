import '../models/audit_entry.dart';
import '../models/consent.dart';
import '../models/estudio_form_definition.dart';
import '../models/evento_clinico.dart';
import '../models/patient.dart';
import '../models/role.dart';

/// Configuración del estudio. Vive como dato, no como constantes en el código.
class StudyConfig {
  const StudyConfig({
    required this.nombreEstudio,
    required this.acronimo,
    required this.consentimientoAprobadoPorCei,
    required this.documentoConsentimiento,
    required this.definicionFormulario,
  });

  final String nombreEstudio;
  final String acronimo;

  /// **Restricción no negociable (CLAUDE.md §13).** Sin este flag el sistema no
  /// admite enrolamiento de pacientes reales. Se gestiona en configuración del
  /// estudio, nunca tocando el código.
  final bool consentimientoAprobadoPorCei;

  final ConsentDocument documentoConsentimiento;
  final EstudioFormDefinition definicionFormulario;
}

/// Se lanza al intentar una operación que el rol no tiene permitida.
/// La UI oculta lo que no corresponde, pero la regla se hace valer aquí:
/// una pantalla mal escrita no debe poder saltarse los permisos.
class PermissionDenied implements Exception {
  const PermissionDenied(this.role, this.accion);

  final Role role;
  final String accion;

  @override
  String toString() => 'El rol ${role.label} no puede $accion.';
}

/// Se lanza al intentar sobrescribir un registro ya enviado sin auditoría.
class SilentEditRejected implements Exception {
  const SilentEditRejected(this.eventoId);

  final String eventoId;

  @override
  String toString() =>
      'El evento $eventoId ya fue registrado: toda corrección exige motivo y '
      'queda en el registro de auditoría.';
}

/// Se lanza al intentar registrar un evento repetible más de una vez cuando su
/// tipo no lo admite.
class EventoNoRepetible implements Exception {
  const EventoNoRepetible(this.tipo);

  final TipoEvento tipo;

  @override
  String toString() =>
      '«${tipo.etiqueta}» solo admite un registro por paciente. Si el dato '
      'anterior es incorrecto, corríjalo — no lo duplique.';
}

/// Acceso a los datos del estudio.
///
/// El MVP la implementa en memoria y sobre SQLite cifrado. Las pantallas hablan
/// solo con esta interfaz, así que sustituir el almacén no las toca.
abstract class StudyRepository {
  StudyConfig get config;

  List<Patient> pacientes({String? recolectorId});
  Patient? paciente(String id);

  /// Todos los eventos registrados de un paciente, en orden cronológico.
  ///
  /// Solo devuelve lo que ocurrió: no hay huecos ni marcadores de ausencia
  /// (CLAUDE.md §4).
  List<EventoClinico> eventosDe(String patientId);

  EventoClinico? evento(String id);

  /// El borrador abierto de ese tipo, si lo hay. Solo puede haber uno a la vez
  /// por tipo y paciente: dos borradores simultáneos del mismo hito serían dos
  /// versiones del mismo dato compitiendo.
  EventoClinico? borradorAbierto(String patientId, TipoEvento tipo);

  List<AuditEntry> auditoria({String? entidadId, int? limite});

  int get registrosEnCola;
  int get dispositivosConCola;

  /// Enrola un paciente. La rama la decide el módulo de aleatorización; el
  /// llamante no puede proponerla — no hay parámetro para ello, a propósito.
  /// La ficha conserva por ahora los campos actuales. Reducirla a lo que pide
  /// el Anexo 4 —código autogenerado, teléfonos e institución— es el paso 5 de
  /// `docs/REENCAMINAMIENTO.md`.
  Patient enrolar({
    required Investigador autor,
    required String nombre,
    required String carneIdentidad,
    required int edad,
    required Sexo sexo,
    required String numeroHistoriaClinica,
    required String telefono,
    required String direccion,
  });

  Consent registrarConsentimiento({
    required Investigador autor,
    required String patientId,
    required List<List<({double x, double y})>> firmaTrazos,
  });

  /// Guarda el borrador abierto de ese tipo, creándolo si no existía.
  EventoClinico guardarBorrador({
    required Investigador autor,
    required String patientId,
    required TipoEvento tipo,
    required DateTime fechaOcurrencia,
    required Map<String, Object?> valores,
  });

  /// Cierra el evento y lo encola para envío. A partir de aquí es inmutable.
  EventoClinico registrarEvento({
    required Investigador autor,
    required String patientId,
    required TipoEvento tipo,
    required DateTime fechaOcurrencia,
    required Map<String, Object?> valores,
  });

  /// Única vía para tocar un evento ya registrado. [motivo] no admite vacío.
  EventoClinico corregirEventoRegistrado({
    required Investigador autor,
    required String eventoId,
    required String campo,
    required Object? valorNuevo,
    required String motivo,
  });
}
