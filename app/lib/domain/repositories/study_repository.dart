import '../models/audit_entry.dart';
import '../models/consent.dart';
import '../models/patient.dart';
import '../models/role.dart';
import '../models/visit.dart';
import '../models/visit_form_definition.dart';

/// Configuración del estudio. Vive como dato, no como constantes en el código.
class StudyConfig {
  const StudyConfig({
    required this.nombreEstudio,
    required this.centro,
    required this.servicio,
    required this.consentimientoAprobadoPorCei,
    required this.documentoConsentimiento,
    required this.definicionFormulario,
  });

  final String nombreEstudio;
  final String centro;
  final String servicio;

  /// Restricción no negociable (CLAUDE.md §8): sin este flag el sistema no
  /// admite enrolamiento de pacientes reales. Se gestiona en configuración del
  /// estudio, nunca tocando el código.
  final bool consentimientoAprobadoPorCei;

  final ConsentDocument documentoConsentimiento;
  final VisitFormDefinition definicionFormulario;
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
  const SilentEditRejected(this.visitId);
  final String visitId;

  @override
  String toString() =>
      'La visita $visitId ya fue enviada: toda corrección exige motivo y queda '
      'en el registro de auditoría.';
}

/// Acceso a los datos del estudio.
///
/// El MVP la implementa en memoria; la implementación real será SQLite cifrado
/// en el dispositivo + cola de sincronización. Las pantallas hablan solo con
/// esta interfaz, así que ese cambio no las toca.
abstract class StudyRepository {
  StudyConfig get config;

  List<Patient> pacientes({String? recolectorId});
  Patient? paciente(String id);

  /// Todas las visitas de un paciente, en orden de día del estudio.
  List<Visit> visitasDe(String patientId);
  Visit? visita(String patientId, int dia);

  List<AuditEntry> auditoria({String? entidadId, int? limite});

  int get registrosEnCola;
  int get dispositivosConCola;

  /// Enrola un paciente. La rama la decide el módulo de aleatorización; el
  /// llamante no puede proponerla.
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

  /// Guarda una visita en borrador. Solo válido si aún no fue enviada.
  Visit guardarBorrador({
    required Investigador autor,
    required String patientId,
    required int dia,
    required Map<String, Object?> valores,
  });

  /// Cierra la visita y la encola para envío. A partir de aquí es inmutable.
  Visit cerrarVisita({
    required Investigador autor,
    required String patientId,
    required int dia,
    required Map<String, Object?> valores,
  });

  /// Única vía para tocar una visita ya enviada. [motivo] no admite vacío.
  Visit corregirVisitaEnviada({
    required Investigador autor,
    required String patientId,
    required int dia,
    required String campo,
    required Object? valorNuevo,
    required String motivo,
  });
}
