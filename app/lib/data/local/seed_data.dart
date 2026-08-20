import '../../domain/models/consent.dart';
import '../../domain/models/estudio_form_definition.dart';
import '../../domain/models/evento_clinico.dart';
import '../../domain/models/role.dart';
import '../../domain/repositories/study_repository.dart';
import '../allocation/allocation_strategy.dart';

/// Configuración y datos de arranque del estudio.
///
/// Nada de aquí es real: ni los investigadores, ni la semilla, ni el texto del
/// consentimiento. El repositorio es público (CLAUDE.md §15).
class Seed {
  const Seed._();

  /// Fecha de referencia de los datos de demostración.
  static final DateTime hoy = DateTime(2026, 8, 20);

  // ── Investigadores de demostración ─────────────────────────────
  //
  // Los roles todavía son los tres del modelo anterior. Sustituirlos por
  // reclutador / aplicador / evaluador / investigador principal es el paso 6
  // de `docs/REENCAMINAMIENTO.md`.
  static const morales = Investigador(
    id: 'u-001',
    usuario: 'investigador.uno',
    nombre: 'Dra. Uno',
    role: Role.recolector,
  );
  static const perez = Investigador(
    id: 'u-002',
    usuario: 'investigador.dos',
    nombre: 'Dr. Dos',
    role: Role.recolector,
  );
  static const betancourt = Investigador(
    id: 'u-003',
    usuario: 'observador.tres',
    nombre: 'Dr. Tres',
    role: Role.observador,
  );
  static const guerra = Investigador(
    id: 'u-004',
    usuario: 'principal.cuatro',
    nombre: 'Dra. Cuatro',
    role: Role.administrador,
  );

  static const investigadores = [morales, perez, betancourt, guerra];

  // ── Definición de formularios ──────────────────────────────────
  //
  // PROVISIONAL. Este es un esqueleto mínimo por evento, trazable a BASES §6,
  // suficiente para que la línea de tiempo funcione y se pueda enseñar.
  //
  // El paso 4 de `docs/REENCAMINAMIENTO.md` lo sustituye por los cuatro módulos
  // completos del Anexo 4, con sus categorías exactas.
  //
  // Los rangos de plausibilidad van casi todos vacíos a propósito: los que
  // había eran de paciente general ambulatorio, y un paciente ventilado en UCI
  // los excede con normalidad. Ponerlos sin validación de un intensivista
  // produciría avisos falsos que el equipo aprendería a ignorar, que es peor
  // que no tenerlos (CLAUDE.md §14 y pendiente §8).
  static const formulario = EstudioFormDefinition(
    version: 'form-v0.2-provisional',
    eventos: [
      EventoDefinicion(
        tipo: TipoEvento.enrolamiento,
        secciones: [
          FormSection(
            titulo: 'Datos generales',
            campos: [
              FieldDefinition(
                key: 'fecha_ingreso_uci',
                label: 'Ingreso a UCI',
                tipo: FieldType.fecha,
                obligatorio: true,
                ancho: 2,
              ),
              FieldDefinition(
                key: 'imc',
                label: 'IMC',
                tipo: FieldType.seleccionUnica,
                ancho: 2,
                opciones: [
                  '<18,5 bajo peso',
                  '18,5–24,9 normopeso',
                  '25–29,9 sobrepeso',
                  '30–39,9 obeso',
                  '>40 superobeso',
                ],
              ),
              FieldDefinition(
                key: 'causa_intubacion',
                label: 'Causa de intubación y VMI',
                tipo: FieldType.seleccionUnica,
                obligatorio: true,
                ancho: 2,
                opciones: [
                  'Respiratoria',
                  'Neurológica',
                  'Cardiovascular',
                  'Metabólica',
                  'Anestésica/quirúrgica',
                  'Paro cardiorrespiratorio',
                  'Shock',
                ],
              ),
              FieldDefinition(
                key: 'comorbilidades',
                label: 'Comorbilidades relevantes',
                tipo: FieldType.seleccionMultiple,
                ancho: 2,
                opciones: ['HTA', 'DM', 'CI', 'IC', 'ERC', 'EPOC', 'AB', 'ECV previa'],
              ),
            ],
          ),
        ],
      ),
      EventoDefinicion(
        tipo: TipoEvento.estratificacionRiesgo,
        secciones: [
          FormSection(
            titulo: 'Parámetros ventilatorios',
            campos: [
              FieldDefinition(
                key: 'fecha_inicio_vmi',
                label: 'Inicio de VMI',
                tipo: FieldType.fecha,
                obligatorio: true,
                ancho: 2,
              ),
              FieldDefinition(
                key: 'fio2',
                label: 'FiO₂',
                unidad: '%',
                tipo: FieldType.numero,
                obligatorio: true,
              ),
              FieldDefinition(
                key: 'peep',
                label: 'PEEP',
                unidad: 'cmH₂O',
                tipo: FieldType.numero,
                obligatorio: true,
              ),
            ],
          ),
        ],
      ),
      EventoDefinicion(
        tipo: TipoEvento.cribado,
        secciones: [
          FormSection(
            titulo: 'Cribado del día',
            campos: [
              FieldDefinition(
                key: 'cumple_criterios',
                label: '¿Cumple criterios de cribado?',
                tipo: FieldType.siNo,
                obligatorio: true,
                ancho: 2,
              ),
              FieldDefinition(
                key: 'observaciones',
                label: 'Observaciones',
                tipo: FieldType.textoLargo,
                ancho: 2,
              ),
            ],
          ),
        ],
      ),
      EventoDefinicion(
        tipo: TipoEvento.evaluacionDiaria,
        secciones: [
          FormSection(
            titulo: 'Evaluación del día',
            campos: [
              FieldDefinition(
                key: 'detencion_sedacion',
                label: '¿Detención diaria de sedación?',
                tipo: FieldType.siNo,
                obligatorio: true,
                ancho: 2,
              ),
              FieldDefinition(
                key: 'evaluacion_ventilacion_espontanea',
                label: '¿Evaluación de ventilación espontánea?',
                tipo: FieldType.siNo,
                obligatorio: true,
                ancho: 2,
              ),
              FieldDefinition(
                key: 'duracion_ventilacion_espontanea',
                label: 'Duración',
                tipo: FieldType.seleccionUnica,
                ancho: 2,
                opciones: ['> 15 min', '10–15 min', '< 10 min'],
              ),
            ],
          ),
        ],
      ),
      EventoDefinicion(
        tipo: TipoEvento.pruebaVentilacionEspontanea,
        secciones: [
          FormSection(
            titulo: 'Método',
            campos: [
              FieldDefinition(
                key: 'metodo_pve',
                label: 'Método empleado',
                tipo: FieldType.seleccionUnica,
                obligatorio: true,
                ancho: 2,
                opciones: ['Tubo en T', 'PSV', 'PSV + PEEP', 'CPAP'],
              ),
            ],
          ),
          FormSection(
            titulo: 'Monitorización al inicio',
            campos: [
              FieldDefinition(
                key: 'rsbi_inicio',
                label: 'RSBI',
                tipo: FieldType.numero,
                obligatorio: true,
                min: 0,
                max: 250,
              ),
              FieldDefinition(
                key: 'fr_inicio',
                label: 'FR',
                unidad: 'rpm',
                tipo: FieldType.numero,
                obligatorio: true,
                min: 5,
                max: 60,
              ),
            ],
          ),
          FormSection(
            titulo: 'Monitorización al final',
            campos: [
              FieldDefinition(
                key: 'rsbi_final',
                label: 'RSBI',
                tipo: FieldType.numero,
                min: 0,
                max: 250,
              ),
              FieldDefinition(
                key: 'fr_final',
                label: 'FR',
                unidad: 'rpm',
                tipo: FieldType.numero,
                min: 5,
                max: 60,
              ),
            ],
          ),
          FormSection(
            titulo: 'Resultado',
            campos: [
              FieldDefinition(
                key: 'resultado_pve',
                label: 'Resultado',
                tipo: FieldType.seleccionUnica,
                obligatorio: true,
                ancho: 2,
                opciones: ['Éxito', 'Fallo'],
              ),
              FieldDefinition(
                key: 'duracion_pve',
                label: 'Duración',
                tipo: FieldType.seleccionUnica,
                ancho: 2,
                opciones: ['< 30 min', '30–60 min', '60–120 min'],
              ),
            ],
          ),
        ],
      ),
      EventoDefinicion(
        tipo: TipoEvento.traqueostomia,
        secciones: [
          FormSection(
            titulo: 'Traqueostomía',
            campos: [
              FieldDefinition(
                key: 'fecha_traqueostomia',
                label: 'Fecha de realización',
                tipo: FieldType.fecha,
                obligatorio: true,
                ancho: 2,
              ),
            ],
          ),
        ],
      ),
      EventoDefinicion(
        tipo: TipoEvento.extubacion,
        secciones: [
          FormSection(
            titulo: 'Extubación',
            campos: [
              FieldDefinition(
                key: 'test_fuga',
                label: '¿Se realizó test de fuga?',
                tipo: FieldType.siNo,
                obligatorio: true,
                ancho: 2,
              ),
              FieldDefinition(
                key: 'resultado_test_fuga',
                label: 'Resultado del test de fuga',
                tipo: FieldType.seleccionUnica,
                ancho: 2,
                opciones: ['Con fuga', 'Sin fuga'],
              ),
              FieldDefinition(
                key: 'duracion_total_vmi',
                label: 'Duración total de VMI',
                unidad: 'días',
                tipo: FieldType.numero,
                obligatorio: true,
              ),
            ],
          ),
        ],
      ),
      EventoDefinicion(
        tipo: TipoEvento.soportePostExtubacion,
        secciones: [
          FormSection(
            titulo: 'Soporte',
            campos: [
              FieldDefinition(
                key: 'tipo_soporte',
                label: 'Tipo de soporte',
                tipo: FieldType.seleccionUnica,
                obligatorio: true,
                ancho: 2,
                opciones: ['HFNC', 'VNI', 'VNI + HFNC'],
              ),
            ],
          ),
        ],
      ),
      EventoDefinicion(
        tipo: TipoEvento.reintubacion,
        secciones: [
          FormSection(
            titulo: 'Reintubación',
            campos: [
              FieldDefinition(
                key: 'reintubacion_72h',
                label: '¿Reintubación en ≤ 72 h?',
                tipo: FieldType.siNo,
                obligatorio: true,
                ancho: 2,
                ayuda: 'Desenlace principal del ensayo',
              ),
              FieldDefinition(
                key: 'causa_reintubacion',
                label: 'Causa',
                tipo: FieldType.seleccionUnica,
                ancho: 2,
                opciones: [
                  'Inestabilidad hemodinámica',
                  'Laringoespasmo',
                  'Broncoaspiración',
                  'Estridor',
                  'Fallo respiratorio agudo',
                  'Deterioro neurológico',
                  'Otra',
                ],
              ),
            ],
          ),
        ],
      ),
      EventoDefinicion(
        tipo: TipoEvento.egresoUci,
        secciones: [
          FormSection(
            titulo: 'Egreso',
            campos: [
              FieldDefinition(
                key: 'estancia_uci',
                label: 'Estancia en UCI',
                unidad: 'días',
                tipo: FieldType.numero,
                obligatorio: true,
              ),
              FieldDefinition(
                key: 'estado_egreso',
                label: 'Estado al egreso',
                tipo: FieldType.seleccionUnica,
                obligatorio: true,
                opciones: ['Vivo', 'Fallecido'],
              ),
            ],
          ),
        ],
      ),
      EventoDefinicion(
        tipo: TipoEvento.seguimientoPostEgreso,
        secciones: [
          FormSection(
            titulo: 'Seguimiento a 28 días',
            campos: [
              FieldDefinition(
                key: 'fallecimiento_post_egreso',
                label: 'Fallecimiento posterior al egreso',
                tipo: FieldType.seleccionUnica,
                obligatorio: true,
                ancho: 2,
                opciones: [
                  'Primeros 7 días',
                  '8–14 días',
                  '15–28 días',
                  'No fallecimiento a 28 días',
                ],
              ),
            ],
          ),
        ],
      ),
    ],
  );

  // ── Consentimiento informado ───────────────────────────────────
  //
  // Texto de demostración. El real está en el Anexo 3 del proyecto y se carga
  // cuando el CEI lo apruebe. Nótese que no dice cuál rama es cuál: el
  // documento que firma el paciente tampoco puede romper el cegamiento.
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

  static StudyConfig get config => const StudyConfig(
        nombreEstudio: 'Liberación de la ventilación mecánica invasiva',
        acronimo: 'LIVERE',
        // Restricción CLAUDE.md §13: en falso hasta que el CEI apruebe. Con el
        // flag en falso la app funciona en modo demostración y bloquea el
        // enrolamiento de pacientes reales.
        consentimientoAprobadoPorCei: false,
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
