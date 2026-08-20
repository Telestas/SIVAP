import '../../domain/models/consent.dart';
import '../../domain/models/estudio_form_definition.dart';
import '../../domain/models/evento_clinico.dart';
import '../../domain/models/institucion.dart';
import '../../domain/models/role.dart';
import '../../domain/repositories/study_repository.dart';
import '../allocation/allocation_strategy.dart';

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
  static const observador = Investigador(
    id: 'u-006',
    usuario: 'investigador.seis',
    nombre: 'Dr. Seis',
    roles: {Rol.observador},
    institucion: militar,
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
    observador,
    reclutadorCardiologia,
  ];

  static Investigador porId(String id) =>
      investigadores.firstWhere((i) => i.id == id);

  // ── Definición de formularios ──────────────────────────────────
  //
  // Los cuatro módulos del Anexo 4, repartidos entre los hitos de BASES §5.
  //
  // Lo que NO se pide aquí, y por qué:
  //
  //  - Código de paciente, teléfonos, institución, edad y sexo → están en la
  //    ficha, no en un evento.
  //  - Protocolo aplicado → lo asigna la aleatorización, nadie lo teclea.
  //  - «Total de PVE intentadas» → se cuenta solo, a partir del número de
  //    eventos de PVE registrados. Es el propio Anexo el que señala que es
  //    derivable, y pedir dos veces el mismo dato es pedir que discrepen.
  //  - Fechas de PVE y de traqueostomía → son la fecha del propio evento.
  //
  // Lo que SÍ se pide aunque parezca derivable —duración total de VMI, fecha de
  // PVE exitosa, tiempo entre PVE y extubación— se conserva a propósito: si el
  // evento de origen falta o se registró mal, el dato derivado se perdería sin
  // que nadie lo notara. Sirven además de comprobación cruzada.
  //
  // **Rangos de plausibilidad: vacíos, pendientes de un intensivista.** Los
  // anteriores (FC 40–140, temp 35–37,5, SpO₂ 92–100) eran de paciente general
  // ambulatorio, y un paciente ventilado en UCI los excede con normalidad.
  // Activarlos sin validar produciría avisos constantes que el equipo
  // aprendería a ignorar, que es peor que no tenerlos. Ver
  // `docs/RANGOS_PENDIENTES.md`.
  static const formulario = EstudioFormDefinition(
    version: 'anexo4-v1',
    eventos: [
      // ── Módulo 1 · Datos generales del paciente ────────────────
      EventoDefinicion(
        tipo: TipoEvento.enrolamiento,
        secciones: [
          FormSection(
            titulo: 'Ingreso',
            campos: [
              FieldDefinition(
                key: 'fecha_ingreso_uci',
                label: 'Fecha de ingreso a UCI',
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
                  '< 18,5 · bajo peso',
                  '18,5–24,9 · normopeso',
                  '25–29,9 · sobrepeso',
                  '30–39,9 · obeso',
                  '> 40 · superobeso',
                ],
              ),
            ],
          ),
          FormSection(
            titulo: 'Motivo de la ventilación',
            campos: [
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
                ayuda: 'HTA hipertensión · DM diabetes · CI cardiopatía '
                    'isquémica · IC insuficiencia cardíaca · ERC enfermedad '
                    'renal crónica · AB asma bronquial',
                opciones: [
                  'HTA',
                  'DM',
                  'CI',
                  'IC',
                  'ERC',
                  'EPOC',
                  'AB',
                  'ECV previa',
                ],
              ),
            ],
          ),
        ],
      ),

      // ── Módulo 2 · Datos ventilatorios ─────────────────────────
      EventoDefinicion(
        tipo: TipoEvento.estratificacionRiesgo,
        secciones: [
          FormSection(
            titulo: 'Ventilación mecánica',
            campos: [
              FieldDefinition(
                key: 'fecha_inicio_vmi',
                label: 'Fecha de inicio de VMI',
                tipo: FieldType.fecha,
                obligatorio: true,
                ancho: 2,
              ),
              FieldDefinition(
                key: 'fecha_primera_evaluacion',
                label: 'Fecha de primera evaluación',
                tipo: FieldType.fecha,
                obligatorio: true,
                ancho: 2,
              ),
            ],
          ),
          FormSection(
            titulo: 'Parámetros en la primera evaluación',
            campos: [
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
            titulo: 'Detención de sedación',
            campos: [
              FieldDefinition(
                key: 'detencion_sedacion',
                label: '¿Se realizó detención diaria de sedación?',
                tipo: FieldType.siNo,
                obligatorio: true,
                ancho: 2,
              ),
              FieldDefinition(
                key: 'duracion_detencion_sedacion',
                label: 'Duración de la detención',
                unidad: 'h',
                tipo: FieldType.numero,
                decimales: 1,
              ),
            ],
          ),
          FormSection(
            titulo: 'Ventilación espontánea',
            campos: [
              FieldDefinition(
                key: 'evaluacion_ventilacion_espontanea',
                label: '¿Se evaluó la ventilación espontánea?',
                tipo: FieldType.siNo,
                obligatorio: true,
                ancho: 2,
              ),
              FieldDefinition(
                key: 'duracion_ventilacion_espontanea',
                label: 'Duración de la evaluación',
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
                label: 'Método de PVE empleado',
                tipo: FieldType.seleccionUnica,
                obligatorio: true,
                ancho: 2,
                opciones: ['Tubo en T', 'PSV', 'PSV + PEEP', 'CPAP'],
              ),
            ],
          ),
          // Los dos bloques de monitorización llevan los mismos campos, con
          // sufijo distinto: el análisis compara inicio contra final.
          FormSection(
            titulo: 'Monitorización al inicio de la PVE',
            campos: [
              FieldDefinition(
                key: 'rsbi_inicio',
                label: 'RSBI',
                tipo: FieldType.seleccionUnica,
                obligatorio: true,
                ancho: 2,
                ayuda: 'Índice de respiración rápida superficial (Tobin)',
                opciones: ['> 105', '≤ 105', '≤ 58'],
              ),
              FieldDefinition(
                key: 'fr_inicio',
                label: 'Frecuencia respiratoria',
                unidad: 'rpm',
                tipo: FieldType.numero,
                obligatorio: true,
              ),
              FieldDefinition(
                key: 'vt_inicio',
                label: 'Vt',
                unidad: 'ml',
                tipo: FieldType.numero,
              ),
              FieldDefinition(
                key: 'vm_inicio',
                label: 'VM',
                unidad: 'L',
                tipo: FieldType.numero,
                decimales: 1,
              ),
              FieldDefinition(
                key: 'pplateau_inicio',
                label: 'Pplateau',
                unidad: 'cmH₂O',
                tipo: FieldType.numero,
              ),
              FieldDefinition(
                key: 'driving_pressure_inicio',
                label: 'Driving pressure',
                unidad: 'cmH₂O',
                tipo: FieldType.numero,
              ),
            ],
          ),
          FormSection(
            titulo: 'Monitorización al final de la PVE',
            campos: [
              FieldDefinition(
                key: 'rsbi_final',
                label: 'RSBI',
                tipo: FieldType.seleccionUnica,
                ancho: 2,
                opciones: ['> 105', '≤ 105', '≤ 58'],
              ),
              FieldDefinition(
                key: 'fr_final',
                label: 'Frecuencia respiratoria',
                unidad: 'rpm',
                tipo: FieldType.numero,
              ),
              FieldDefinition(
                key: 'vt_final',
                label: 'Vt',
                unidad: 'ml',
                tipo: FieldType.numero,
              ),
              FieldDefinition(
                key: 'vm_final',
                label: 'VM',
                unidad: 'L',
                tipo: FieldType.numero,
                decimales: 1,
              ),
              FieldDefinition(
                key: 'pplateau_final',
                label: 'Pplateau',
                unidad: 'cmH₂O',
                tipo: FieldType.numero,
              ),
              FieldDefinition(
                key: 'driving_pressure_final',
                label: 'Driving pressure',
                unidad: 'cmH₂O',
                tipo: FieldType.numero,
              ),
            ],
          ),
          FormSection(
            titulo: 'Resultado',
            campos: [
              FieldDefinition(
                key: 'resultado_pve',
                label: 'Resultado de la PVE',
                tipo: FieldType.seleccionUnica,
                obligatorio: true,
                ancho: 2,
                opciones: ['Éxito', 'Fallo'],
              ),
              FieldDefinition(
                key: 'duracion_pve',
                label: 'Duración de la PVE',
                tipo: FieldType.seleccionUnica,
                obligatorio: true,
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
              // La fecha es la del propio evento; no se pide dos veces.
              FieldDefinition(
                key: 'observaciones',
                label: 'Observaciones',
                tipo: FieldType.textoLargo,
                ancho: 2,
                ayuda: 'La fecha de realización es la fecha de este registro.',
              ),
            ],
          ),
        ],
      ),

      // ── Módulo 3 · Evaluación para extubación ──────────────────
      EventoDefinicion(
        tipo: TipoEvento.extubacion,
        secciones: [
          FormSection(
            titulo: 'Test de fuga',
            campos: [
              FieldDefinition(
                key: 'test_fuga',
                label: '¿Se realizó test de fuga?',
                tipo: FieldType.siNo,
                obligatorio: true,
                ancho: 2,
                ayuda: 'Estima el riesgo de estridor tras retirar el tubo',
              ),
              FieldDefinition(
                key: 'resultado_test_fuga',
                label: 'Resultado',
                tipo: FieldType.seleccionUnica,
                ancho: 2,
                opciones: ['Con fuga', 'Sin fuga'],
              ),
            ],
          ),
          FormSection(
            titulo: 'Tiempos',
            campos: [
              FieldDefinition(
                key: 'fecha_pve_exitosa',
                label: 'Fecha de la PVE exitosa',
                tipo: FieldType.fecha,
                obligatorio: true,
                ancho: 2,
              ),
              FieldDefinition(
                key: 'tiempo_pve_extubacion',
                label: 'Tiempo entre PVE exitosa y extubación',
                unidad: 'h',
                tipo: FieldType.numero,
                decimales: 1,
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

      // ── Módulo 4 · Desenlaces clínicos ─────────────────────────
      EventoDefinicion(
        tipo: TipoEvento.soportePostExtubacion,
        secciones: [
          FormSection(
            titulo: 'Soporte respiratorio',
            campos: [
              // Se registra también cuando la respuesta es «No»: la ausencia de
              // registro sería ambigua —¿no hubo soporte, o no se anotó?— y esa
              // ambigüedad no se puede resolver después.
              FieldDefinition(
                key: 'soporte_post_extubacion',
                label: '¿Hubo soporte tras la extubación?',
                tipo: FieldType.siNo,
                obligatorio: true,
                ancho: 2,
              ),
              FieldDefinition(
                key: 'tipo_soporte',
                label: 'Tipo de soporte',
                tipo: FieldType.seleccionUnica,
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
            titulo: 'Desenlace principal',
            campos: [
              FieldDefinition(
                key: 'reintubacion_72h',
                label: '¿Reintubación en ≤ 72 h?',
                tipo: FieldType.siNo,
                obligatorio: true,
                ancho: 2,
                ayuda: 'Extubación fallida — es el desenlace principal del '
                    'ensayo. Se registra siempre, también cuando la respuesta '
                    'es que no.',
              ),
              FieldDefinition(
                key: 'causa_reintubacion',
                label: 'Causa de la reintubación',
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
          FormSection(
            titulo: 'Eventos adversos post-extubación',
            campos: [
              FieldDefinition(
                key: 'eventos_adversos',
                label: 'Eventos adversos',
                tipo: FieldType.seleccionMultiple,
                ancho: 2,
                ayuda: 'Se recogen aquí porque este registro existe siempre, '
                    'haya habido reintubación o no.',
                opciones: [
                  'Ninguna',
                  'Laringoespasmo',
                  'Broncoaspiración',
                  'Estridor',
                  'Fallo respiratorio agudo',
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
                label: 'Duración de la estancia en UCI',
                unidad: 'días',
                tipo: FieldType.numero,
                obligatorio: true,
                ancho: 2,
              ),
              FieldDefinition(
                key: 'estado_egreso',
                label: 'Estado al egreso de UCI',
                tipo: FieldType.seleccionUnica,
                obligatorio: true,
                ancho: 2,
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

  static StudyConfig get config => const StudyConfig(
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
