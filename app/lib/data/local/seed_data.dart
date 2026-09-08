import '../../domain/models/consent.dart';
import '../../domain/models/institucion.dart';
import '../../domain/models/role.dart';
import '../../domain/repositories/study_repository.dart';
import '../allocation/allocation_strategy.dart';
import 'anexo4.dart';

/// Configuración y datos de arranque del estudio.
///
/// Nada de aquí es real: ni los investigadores, ni los centros, ni la semilla,
/// ni el texto del consentimiento. El repositorio es público (CLAUDE.md §15).
class Seed {
  const Seed._();

  /// Fecha de referencia de los datos de demostración.
  static final DateTime hoy = DateTime(2026, 8, 20);

  // ── Centros participantes ──────────────────────────────────────
  //
  // Descriptores genéricos. El catálogo real —con los nombres de los tres
  // hospitales— es configuración del estudio y no se versiona (CLAUDE.md §15).
  // El `codigo` es el prefijo del código de paciente: cambiarlo rompería los
  // códigos ya emitidos.
  static const coordinador = Institucion(
    codigo: 'HC',
    nombre: 'Hospital clínico-quirúrgico docente',
    coordinador: true,
  );
  static const cardiologia = Institucion(
    codigo: 'IC',
    nombre: 'Instituto de cardiología y cirugía cardiovascular',
  );
  static const militar = Institucion(
    codigo: 'HM',
    nombre: 'Hospital militar central',
  );

  static const instituciones = [coordinador, cardiologia, militar];

  // ── Investigadores de demostración ─────────────────────────────
  //
  // Uno por función, para poder recorrer la app con cada una y comprobar qué
  // ve y qué no. El primero acumula reclutador y aplicador, que es lo habitual
  // en un equipo pequeño y no compromete el cegamiento — la combinación que sí
  // lo rompe es aplicador + evaluador de desenlaces.
  static const reclutador = Investigador(
    id: 'u-001',
    usuario: 'investigador.uno',
    nombre: 'Dra. Uno',
    roles: {Rol.reclutador, Rol.aplicador},
    institucion: coordinador,
  );
  static const aplicador = Investigador(
    id: 'u-002',
    usuario: 'investigador.dos',
    nombre: 'Dr. Dos',
    roles: {Rol.aplicador},
    institucion: cardiologia,
  );
  static const evaluador = Investigador(
    id: 'u-003',
    usuario: 'investigador.tres',
    nombre: 'Dra. Tres',
    roles: {Rol.evaluadorDesenlaces},
    institucion: coordinador,
  );
  static const analista = Investigador(
    id: 'u-004',
    usuario: 'investigador.cuatro',
    nombre: 'Dr. Cuatro',
    roles: {Rol.analista},
    institucion: coordinador,
  );
  static const principal = Investigador(
    id: 'u-005',
    usuario: 'investigador.cinco',
    nombre: 'Dra. Cinco',
    roles: {Rol.investigadorPrincipal},
    institucion: coordinador,
  );
  /// Cada centro necesita su reclutador: quien enrola en un hospital no es
  /// alguien de otro, y el rol de reclutador no lo cubre el aplicador.
  static const reclutadorCardiologia = Investigador(
    id: 'u-007',
    usuario: 'investigador.siete',
    nombre: 'Dra. Siete',
    roles: {Rol.reclutador},
    institucion: cardiologia,
  );

  static const investigadores = [
    reclutador,
    aplicador,
    evaluador,
    analista,
    principal,
    reclutadorCardiologia,
  ];

  static Investigador porId(String id) =>
      investigadores.firstWhere((i) => i.id == id);

  // ── Definición de formularios ──────────────────────────────────
  //
  // El Anexo 4 vive en `anexo4.dart`: son quinientas líneas de datos y aquí
  // dentro tapaban todo lo demás. Este alias existe para no tocar a quien ya
  // lo usaba.
  static final formulario = Anexo4.definicion;

  // ── Consentimiento informado ───────────────────────────────────
  //
  // Texto de demostración. El real está en el Anexo 3 del proyecto y se carga
  // cuando el CEI lo apruebe. No dice cuál rama es cuál: el documento que firma
  // el paciente tampoco puede romper el cegamiento.
  static const documentoConsentimiento = ConsentDocument(
    version: 'v0.1-demostración',
    codigoCei: 'CEI pendiente',
    vigenteDesde: 'sin aprobar',
    parrafos: [
      'Se le invita a participar en un ensayo clínico que compara dos protocolos '
          'de retirada de la ventilación mecánica en cuidados intensivos. La '
          'asignación a uno de los dos protocolos se realiza de forma aleatoria y '
          'no depende de su médico ni de su estado.',
      'Su participación es voluntaria. Puede retirarse en cualquier momento sin '
          'que ello afecte la atención médica que recibe.',
      'Sus datos clínicos se registran con un código interno. El análisis '
          'estadístico se realiza sobre datos sin su nombre ni su contacto.',
      'Este texto es una muestra para probar el sistema. El documento definitivo '
          'es el aprobado por el Comité de Ética de la Investigación.',
    ],
    declaraciones: [
      'He leído el documento y se me explicó verbalmente en un lenguaje comprensible.',
      'Acepto participar y que mis datos clínicos se usen con fines de investigación.',
    ],
  );

  static StudyConfig get config => StudyConfig(
        nombreEstudio: 'Liberación de la ventilación mecánica invasiva',
        acronimo: 'LIVERE',
        instituciones: instituciones,
        // Restricción CLAUDE.md §13: en falso hasta que el CEI apruebe. Con el
        // flag en falso la app funciona en modo demostración y bloquea el
        // enrolamiento de pacientes reales.
        consentimientoAprobadoPorCei: false,
        // PENDIENTE de la investigadora principal. En `true` mientras no se
        // decida, porque en un equipo pequeño acumular funciones es lo normal;
        // la app avisa cuando la combinación compromete el cegamiento.
        permiteAcumularRoles: true,
        documentoConsentimiento: documentoConsentimiento,
        definicionFormulario: formulario,
      );

  // ── Secuencia de aleatorización ────────────────────────────────
  //
  // Semilla FALSA, de demostración. La real se genera desde `/dev/urandom`, se
  // anota en el expediente en papel y NUNCA entra al repositorio ni a la app
  // (CLAUDE.md §7).
  static const semillaDemostracion = 20260814;
  static const longitudSecuencia = 120;

  static final secuenciaAleatorizacion = AllocationSequence.generada(
    semilla: semillaDemostracion,
    longitud: longitudSecuencia,
    ahora: DateTime(2026, 8, 14),
    etiqueta: 'secuencia de demostración',
  );
}
