import '../models/audit_entry.dart';
import '../models/consent.dart';
import '../models/estudio_form_definition.dart';
import '../models/evento_clinico.dart';
import '../models/institucion.dart';
import '../models/patient.dart';
import '../models/role.dart';

/// Configuración del estudio. Vive como dato, no como constantes en el código.
class StudyConfig {
  const StudyConfig({
    required this.nombreEstudio,
    required this.acronimo,
    required this.instituciones,
    required this.consentimientoAprobadoPorCei,
    required this.permiteAcumularRoles,
    required this.documentoConsentimiento,
    required this.definicionFormulario,
  });

  final String nombreEstudio;
  final String acronimo;

  /// Centros participantes (CLAUDE.md §8). El catálogo real es configuración
  /// del estudio: los nombres de los hospitales no se versionan (§15).
  final List<Institucion> instituciones;

  /// Si un mismo investigador puede acumular funciones.
  ///
  /// Decisión de la investigadora principal, no del desarrollo. En equipos
  /// pequeños es frecuente y a veces inevitable; la combinación que sí rompe el
  /// cegamiento es aplicador + evaluador de desenlaces en la misma persona
  /// (`Investigador.acumulaFuncionesIncompatibles`).
  final bool permiteAcumularRoles;

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
  const PermissionDenied(this.quien, this.accion);

  final Investigador quien;
  final String accion;

  @override
  String toString() => '${quien.etiquetaRoles} no puede $accion.';
}

/// Se lanza al intentar capturar un hito que la función del usuario no cubre.
///
/// No es un permiso administrativo: es la separación de funciones que el
/// cegamiento exige (BASES §4). Que un aplicador registre desenlaces anularía
/// la independencia de la evaluación.
class FueraDeSuFuncion implements Exception {
  const FueraDeSuFuncion(this.quien, this.tipo);

  final Investigador quien;
  final TipoEvento tipo;

  @override
  String toString() =>
      '«${tipo.etiqueta}» no corresponde a ${quien.etiquetaRoles}. Lo registra '
      'otra función del equipo.';
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
  ///
  /// El código del paciente lo genera el sistema con el prefijo del centro. Ni
  /// el carné de identidad ni la dirección se piden: el Anexo 4 no los necesita
  /// y cada dato personal almacenado hay que justificarlo (CLAUDE.md §9).
  Patient enrolar({
    required Investigador autor,
    required Institucion institucion,
    required String nombre,
    required String numeroHistoriaClinica,
    required String telefonoPrincipal,
    required int edad,
    required Sexo sexo,
    String? telefonoSecundario,
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
