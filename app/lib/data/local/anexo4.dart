import '../../domain/models/estudio_form_definition.dart';
import '../../domain/models/evento_clinico.dart';

/// El Anexo 4 del ensayo, como datos.
///
/// **Restricción CLAUDE.md §5**: los campos son una estructura de datos, no
/// pantallas escritas a mano. Ajustar el protocolo es editar este archivo —a
/// futuro, publicar una versión nueva desde el servidor—, no recompilar la app.
///
/// La `key` de cada campo es la columna del dataset exportado. Cambiar un
/// `label` es cosmético; cambiar una `key` rompe el dataset y obliga a
/// reconciliar a mano lo ya capturado.
///
/// ── Qué NO se pide aquí, y por qué ──────────────────────────────
///
///  - Nombre, apellidos, teléfonos, historia clínica, centro, edad y sexo →
///    están en la ficha del paciente, no en un evento (CLAUDE.md §1). El Anexo
///    los junta porque es un formulario de papel; aquí van separados para poder
///    exportar el dataset clínico sin identidad.
///  - Protocolo aplicado → lo asigna la aleatorización. Nadie lo teclea, y
///    nadie lo elige (CLAUDE.md §6).
///  - «¿Se realizó PVE?» dentro del formulario de PVE → si el registro existe,
///    la prueba se hizo. Un evento que no ocurrió no tiene fila (§4).
///  - Fecha de la PVE, fecha de la PVE exitosa, fecha de extubación → son la
///    fecha del propio evento.
///  - «Total de PVE intentadas» → se cuenta solo, de los registros de PVE.
///    Pedir dos veces el mismo dato es pedir que discrepen.
///  - «Edad ☐<65 ☐≥65» → se deduce de la edad. El factor de riesgo por edad sí
///    se marca aparte, porque forma parte del instrumento de estratificación.
///
/// ── Dónde esta definición se aparta del documento, y por qué ────
///
/// Todo lo de aquí abajo está pendiente de que lo confirme la investigadora
/// principal. Ver `docs/ANEXO4_CAMBIOS.md`.
///
///  1. **Tramos de categorías sin huecos ni solapes.** El documento escribe
///     «6-14 días» y «>15 días»: un paciente con 15 días exactos no tenía
///     casilla. Igual con el soporte post-extubación, que se acababa en 72 h
///     cuando las hay más largas, y con las duraciones de PVE, que se solapaban
///     en 60 y en 120 minutos. Aquí los tramos son contiguos y disjuntos.
///  2. **Causa de la intubación, mutuamente excluyente.** El documento admite
///     una sola marca pero ofrece «Respiratoria» y «EPOC exacerbada», que no
///     son alternativas. Importa porque «causa EPOC exacerbada» es uno de los
///     cinco factores de riesgo: dos médicos codificarían distinto y al mismo
///     paciente le saldría un riesgo distinto. Las categorías generales llevan
///     ahora «(otras causas)».
///  3. **El seguimiento post-egreso es un registro por contacto**, no tres
///     casillas en un formulario. Con tres casillas, el registro se queda en
///     borrador 28 días —y los borradores no se sincronizan—, así que el dato
///     viviría cuatro semanas en un solo teléfono. Es el riesgo que más pesa
///     hoy en el proyecto.
class Anexo4 {
  const Anexo4._();

  /// Modos ventilatorios. La misma lista antes de la PVE y antes de extubar:
  /// si divergieran, el dataset tendría dos vocabularios para lo mismo.
  static const modosVentilatorios = [
    'IPPV',
    'IPPV + Autoflow',
    'PS',
    'CPAP',
    'SIMV',
    'SIMV + PS',
    'PC',
    'VC',
    'MMV',
    'BIPAP',
    'APRV',
    'PRVC',
    'Otro modo',
  ];

  static const definicion = EstudioFormDefinition(
    version: 'anexo4-v2',
    eventos: [
      _enrolamiento,
      _cribado,
      _pruebaVentilacionEspontanea,
      _extubacion,
      _desenlaces,
      _seguimientoPostEgreso,
    ],
  );

  // ══════════════════════════════════════════════════════════════
  // Módulo 1 · Enrolamiento
  // ══════════════════════════════════════════════════════════════

  static const _enrolamiento = EventoDefinicion(
    tipo: TipoEvento.enrolamiento,
    secciones: [
      FormSection(
        titulo: 'Criterios de exclusión',
        esPuertaDeExclusion: true,
        mensajeAlExcluir: 'Paciente no elegible para el estudio.',
        campos: [
          FieldDefinition(
            key: 'exclusion_neuromuscular',
            label: 'Trastorno neuromuscular grave',
            tipo: FieldType.siNo,
            ancho: 2,
          ),
          FieldDefinition(
            key: 'exclusion_glasgow',
            label: 'Glasgow igual o menor de 8 puntos',
            tipo: FieldType.siNo,
            ancho: 2,
          ),
          FieldDefinition(
            key: 'exclusion_traqueostomia',
            label: 'Traqueostomía ya presente',
            tipo: FieldType.siNo,
            ancho: 2,
          ),
          FieldDefinition(
            key: 'exclusion_paliativos',
            label: 'Cuidados paliativos o limitación del esfuerzo terapéutico',
            tipo: FieldType.siNo,
            ancho: 2,
          ),
          FieldDefinition(
            key: 'exclusion_otro_ensayo',
            label: 'Participa a la vez en otro ensayo clínico',
            tipo: FieldType.siNo,
            ancho: 2,
          ),
        ],
      ),
      FormSection(
        titulo: 'Ventilación mecánica',
        campos: [
          FieldDefinition(
            key: 'fecha_ingreso_uci',
            label: 'Fecha de ingreso a UCI',
            tipo: FieldType.fecha,
            obligatorio: true,
          ),
          FieldDefinition(
            key: 'fecha_inicio_vmi',
            label: 'Fecha de inicio de VMI',
            tipo: FieldType.fecha,
            obligatorio: true,
          ),
          FieldDefinition(
            key: 'causa_intubacion',
            label: 'Causa de la intubación y la VMI',
            tipo: FieldType.seleccionUnica,
            obligatorio: true,
            ancho: 2,
            // Excluyentes de verdad: las generales llevan «(otras causas)»
            // para que un EPOC descompensado no pueda codificarse de dos
            // formas. Ver la nota 2 de la cabecera.
            opciones: [
              'Respiratoria (otras causas)',
              'EPOC exacerbada',
              'Neurológica',
              'Cardiovascular (otras causas)',
              'Insuficiencia cardíaca',
              'Metabólica',
              'Anestésica o quirúrgica',
              'Paro cardiorrespiratorio',
              'Shock',
              'Politrauma',
            ],
          ),
          FieldDefinition(
            key: 'via_aerea_dificil',
            label: 'Vía aérea difícil',
            tipo: FieldType.siNo,
          ),
          FieldDefinition(
            key: 'tot_menor_igual_65',
            label: 'TOT de 6,5 mm o menor',
            tipo: FieldType.siNo,
          ),
        ],
      ),
      FormSection(
        titulo: 'Antropometría',
        campos: [
          FieldDefinition(
            key: 'peso',
            label: 'Peso conocido o estimado',
            unidad: 'kg',
            tipo: FieldType.numero,
            obligatorio: true,
          ),
          FieldDefinition(
            key: 'talla',
            label: 'Talla conocida o estimada',
            unidad: 'm',
            tipo: FieldType.numero,
            obligatorio: true,
            decimales: 2,
          ),
          FieldDefinition(
            key: 'imc',
            label: 'IMC',
            unidad: 'kg/m²',
            tipo: FieldType.numero,
            decimales: 1,
            calculo: Calculo.imc,
            entradasDelCalculo: ['peso', 'talla'],
          ),
          FieldDefinition(
            key: 'categoria_imc',
            label: 'Categoría',
            tipo: FieldType.seleccionUnica,
            opciones: [
              'Bajo peso',
              'Normopeso',
              'Sobrepeso',
              'Obeso',
              'Superobeso',
            ],
            calculo: Calculo.categoriaImc,
            entradasDelCalculo: ['imc'],
          ),
        ],
      ),
      FormSection(
        titulo: 'Estratificación de riesgo',
        campos: [
          FieldDefinition(
            key: 'factor_edad',
            label: 'Edad mayor de 65 años',
            tipo: FieldType.siNo,
            ancho: 2,
          ),
          FieldDefinition(
            key: 'factor_obesidad',
            label: 'Obeso o superobeso',
            tipo: FieldType.siNo,
            ancho: 2,
            ayuda: 'Comprobar contra el IMC calculado arriba.',
          ),
          FieldDefinition(
            key: 'factor_epoc',
            label: 'Intubado por EPOC exacerbada',
            tipo: FieldType.siNo,
            ancho: 2,
          ),
          FieldDefinition(
            key: 'factor_insuficiencia_cardiaca',
            label: 'Intubado por insuficiencia cardíaca',
            tipo: FieldType.siNo,
            ancho: 2,
          ),
          FieldDefinition(
            key: 'factor_via_aerea',
            label: 'Vía aérea difícil o TOT de 6,5 mm o menor',
            tipo: FieldType.siNo,
            ancho: 2,
          ),
          FieldDefinition(
            key: 'estratificacion_riesgo',
            label: 'Nivel de riesgo',
            tipo: FieldType.seleccionUnica,
            ancho: 2,
            opciones: ['Bajo', 'Moderado', 'Alto'],
            ayuda: 'Alto con 4 factores o más · Moderado de 1 a 3 · Bajo con '
                'ninguno.',
            calculo: Calculo.estratificacionRiesgo,
            entradasDelCalculo: [
              'factor_edad',
              'factor_obesidad',
              'factor_epoc',
              'factor_insuficiencia_cardiaca',
              'factor_via_aerea',
            ],
          ),
        ],
      ),
      FormSection(
        titulo: 'Comorbilidades',
        campos: [
          FieldDefinition(
            key: 'comorbilidades',
            label: 'Comorbilidades relevantes',
            tipo: FieldType.seleccionMultiple,
            ancho: 2,
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
  );

  // ══════════════════════════════════════════════════════════════
  // Módulo 2 · Cribado — se repite a diario
  // ══════════════════════════════════════════════════════════════

  static const _cribado = EventoDefinicion(
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
            ayuda: 'Al marcar «Sí», el paciente pasa al módulo de destete.',
          ),
        ],
      ),
    ],
  );

  // ══════════════════════════════════════════════════════════════
  // Módulo 3 · Prueba de ventilación espontánea — se repite
  // ══════════════════════════════════════════════════════════════

  static const _pruebaVentilacionEspontanea = EventoDefinicion(
    tipo: TipoEvento.pruebaVentilacionEspontanea,
    secciones: [
      FormSection(
        titulo: 'La prueba',
        campos: [
          FieldDefinition(
            key: 'modo_ventilatorio_previo',
            label: 'Modo ventilatorio antes de la PVE',
            tipo: FieldType.seleccionUnica,
            obligatorio: true,
            ancho: 2,
            opciones: modosVentilatorios,
          ),
          FieldDefinition(
            key: 'modo_ventilatorio_previo_otro',
            label: '¿Cuál?',
            tipo: FieldType.texto,
            ancho: 2,
            dependeDe: 'modo_ventilatorio_previo',
            visibleCuando: ['Otro modo'],
          ),
          FieldDefinition(
            key: 'metodo_pve',
            label: 'Método empleado',
            tipo: FieldType.seleccionUnica,
            obligatorio: true,
            ancho: 2,
            opciones: ['Tubo en T', 'PSV', 'PSV + PEEP', 'CPAP'],
          ),
          FieldDefinition(
            key: 'duracion_pve',
            label: 'Duración de la prueba',
            tipo: FieldType.seleccionUnica,
            obligatorio: true,
            ancho: 2,
            // Contiguos y disjuntos: «30-60» y «60-120» dejaban una PVE de 60
            // minutos exactos en dos casillas a la vez.
            opciones: [
              'Menos de 30 min',
              'De 30 a 59 min',
              'De 60 a 119 min',
              '120 min o más',
            ],
          ),
          FieldDefinition(
            key: 'resultado_pve',
            label: 'Resultado',
            tipo: FieldType.seleccionUnica,
            obligatorio: true,
            ancho: 2,
            opciones: ['Éxito', 'Fallo'],
          ),
        ],
      ),
      FormSection(
        titulo: 'Si la prueba falló',
        campos: [
          FieldDefinition(
            key: 'causa_fallo_pve',
            label: 'Causa principal del fallo',
            tipo: FieldType.seleccionUnica,
            ancho: 2,
            dependeDe: 'resultado_pve',
            visibleCuando: ['Fallo'],
            opciones: [
              'Sedación o relajación residual',
              'Debilidad muscular (PIM o NIF)',
              'Disfunción diafragmática por ecografía',
              'Asincronías',
              'Ansiedad extrema',
              'Temor a asumir la respiración',
              'Delirium',
              'Encefalopatía',
              'Broncoespasmo',
              'Secreciones abundantes o tos ineficaz',
              'Obstrucción del TOT',
              'Atelectasia',
              'Infección no resuelta',
              'Edema pulmonar no cardiogénico (WIPO)',
              'Acidosis respiratoria',
              'Acidosis metabólica',
              'HTA severa',
              'Hipotensión severa o shock',
              'Arritmias cardíacas',
              'Disfunción aguda del ventrículo izquierdo',
              'Hipopotasemia',
            ],
          ),
        ],
      ),
    ],
  );

  // ══════════════════════════════════════════════════════════════
  // Módulo 4 · Extubación y post-extubación
  // ══════════════════════════════════════════════════════════════

  static const _extubacion = EventoDefinicion(
    tipo: TipoEvento.extubacion,
    secciones: [
      FormSection(
        titulo: 'Traqueostomía',
        campos: [
          FieldDefinition(
            key: 'traqueostomia',
            label: '¿Se realizó traqueostomía para avanzar en el destete?',
            tipo: FieldType.siNo,
            obligatorio: true,
            ancho: 2,
          ),
          FieldDefinition(
            key: 'fecha_traqueostomia',
            label: 'Fecha de la traqueostomía',
            tipo: FieldType.fecha,
            ancho: 2,
            dependeDe: 'traqueostomia',
            visibleCuando: [true],
          ),
        ],
      ),
      FormSection(
        titulo: 'Extubación',
        campos: [
          FieldDefinition(
            key: 'modo_ventilatorio_previo_extubacion',
            label: 'Modo ventilatorio antes de extubar',
            tipo: FieldType.seleccionUnica,
            ancho: 2,
            opciones: modosVentilatorios,
          ),
          FieldDefinition(
            key: 'modo_ventilatorio_previo_extubacion_otro',
            label: '¿Cuál?',
            tipo: FieldType.texto,
            ancho: 2,
            dependeDe: 'modo_ventilatorio_previo_extubacion',
            visibleCuando: ['Otro modo'],
          ),
          FieldDefinition(
            key: 'test_fuga',
            label: '¿Se realizó test de fuga?',
            tipo: FieldType.siNo,
          ),
          FieldDefinition(
            key: 'resultado_test_fuga',
            label: 'Resultado del test de fuga',
            tipo: FieldType.seleccionUnica,
            opciones: ['Con fuga', 'Sin fuga'],
            dependeDe: 'test_fuga',
            visibleCuando: [true],
          ),
          FieldDefinition(
            key: 'esteroides_iv_previos',
            label: '¿Esteroides IV antes de extubar?',
            tipo: FieldType.siNo,
            ancho: 2,
          ),
          FieldDefinition(
            key: 'tiempo_pve_extubacion',
            label: 'Tiempo entre la PVE exitosa y la extubación',
            tipo: FieldType.seleccionUnica,
            ancho: 2,
            opciones: [
              'Menos de 1 hora',
              'De 1 a 3 horas',
              'De 4 a 11 horas',
              '12 horas o más',
            ],
          ),
        ],
      ),
      FormSection(
        titulo: 'Soporte post-extubación',
        campos: [
          FieldDefinition(
            key: 'soporte_post_extubacion',
            label: '¿Se empleó soporte tras extubar?',
            tipo: FieldType.siNo,
            ancho: 2,
          ),
          FieldDefinition(
            key: 'tipo_soporte',
            label: 'Tipo de soporte',
            tipo: FieldType.seleccionUnica,
            ancho: 2,
            dependeDe: 'soporte_post_extubacion',
            visibleCuando: [true],
            opciones: [
              'Oxígeno a bajo flujo',
              'CNAF',
              'VNI',
              'VNI + CNAF',
            ],
          ),
          FieldDefinition(
            key: 'tiempo_soporte',
            label: 'Tiempo de uso del soporte',
            tipo: FieldType.seleccionUnica,
            ancho: 2,
            dependeDe: 'soporte_post_extubacion',
            visibleCuando: [true],
            // El documento se acababa en 72 h. Las hay más largas, y sin
            // casilla el dato se pierde o se fuerza en la que no es.
            opciones: [
              'Menos de 24 h',
              'De 24 a 47 h',
              'De 48 a 71 h',
              '72 h o más',
            ],
          ),
        ],
      ),
      FormSection(
        titulo: 'Ventilación mecánica',
        campos: [
          FieldDefinition(
            key: 'duracion_total_vmi',
            label: 'Duración total de la VMI',
            tipo: FieldType.seleccionUnica,
            ancho: 2,
            opciones: ['5 días o menos', 'De 6 a 14 días', '15 días o más'],
          ),
        ],
      ),
    ],
  );

  // ══════════════════════════════════════════════════════════════
  // Módulo 5 · Desenlaces — los captura el evaluador
  // ══════════════════════════════════════════════════════════════

  static const _desenlaces = EventoDefinicion(
    tipo: TipoEvento.desenlaces,
    secciones: [
      FormSection(
        titulo: 'Tras la extubación',
        campos: [
          FieldDefinition(
            key: 'eventos_adversos',
            label: 'Eventos adversos post-extubación',
            tipo: FieldType.seleccionMultiple,
            ancho: 2,
            opciones: [
              'Ninguno',
              'Laringoespasmo',
              'Broncoaspiración',
              'Estridor',
              'Fallo respiratorio agudo',
            ],
          ),
          FieldDefinition(
            key: 'reintubacion_72h',
            label: '¿Reintubación en 72 h o menos?',
            tipo: FieldType.siNo,
            obligatorio: true,
            ancho: 2,
            ayuda: 'Desenlace principal del ensayo.',
          ),
          FieldDefinition(
            key: 'causa_reintubacion',
            label: 'Causa de la reintubación',
            tipo: FieldType.seleccionUnica,
            ancho: 2,
            dependeDe: 'reintubacion_72h',
            visibleCuando: [true],
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
          FieldDefinition(
            key: 'causa_reintubacion_otra',
            label: '¿Cuál?',
            tipo: FieldType.texto,
            ancho: 2,
            dependeDe: 'causa_reintubacion',
            visibleCuando: ['Otra'],
          ),
        ],
      ),
      FormSection(
        titulo: 'Egreso de la unidad',
        campos: [
          FieldDefinition(
            key: 'estancia_uci',
            label: 'Duración de la estancia en UCI',
            tipo: FieldType.seleccionUnica,
            ancho: 2,
            opciones: ['5 días o menos', 'De 6 a 14 días', '15 días o más'],
          ),
          FieldDefinition(
            key: 'estado_egreso',
            label: 'Estado al egreso',
            tipo: FieldType.seleccionUnica,
            obligatorio: true,
            ancho: 2,
            opciones: ['Vivo', 'Fallecido'],
          ),
          FieldDefinition(
            key: 'fecha_egreso_uci',
            label: 'Fecha de egreso de UCI',
            tipo: FieldType.fecha,
            ancho: 2,
            dependeDe: 'estado_egreso',
            visibleCuando: ['Vivo'],
            ayuda: 'Desde esta fecha se cuentan los contactos de seguimiento.',
          ),
          FieldDefinition(
            key: 'fecha_fallecimiento',
            label: 'Fecha del fallecimiento',
            tipo: FieldType.fecha,
            dependeDe: 'estado_egreso',
            visibleCuando: ['Fallecido'],
          ),
          FieldDefinition(
            key: 'causa_fallecimiento',
            label: 'Causa del fallecimiento',
            tipo: FieldType.texto,
            dependeDe: 'estado_egreso',
            visibleCuando: ['Fallecido'],
          ),
        ],
      ),
    ],
  );

  // ══════════════════════════════════════════════════════════════
  // Seguimiento post-egreso — un registro por contacto
  // ══════════════════════════════════════════════════════════════

  static const _seguimientoPostEgreso = EventoDefinicion(
    tipo: TipoEvento.seguimientoPostEgreso,
    secciones: [
      FormSection(
        titulo: 'Contacto de seguimiento',
        campos: [
          FieldDefinition(
            key: 'ventana_contacto',
            label: 'Momento del contacto',
            tipo: FieldType.seleccionUnica,
            obligatorio: true,
            ancho: 2,
            opciones: [
              'Día 7 tras el egreso',
              'Día 14 tras el egreso',
              'Día 28 tras el egreso',
            ],
          ),
          FieldDefinition(
            key: 'fallecido',
            label: '¿Ha fallecido el paciente?',
            tipo: FieldType.siNo,
            obligatorio: true,
            ancho: 2,
          ),
          FieldDefinition(
            key: 'causa_fallecimiento',
            label: 'Causa del fallecimiento',
            tipo: FieldType.texto,
            ancho: 2,
            dependeDe: 'fallecido',
            visibleCuando: [true],
          ),
        ],
      ),
    ],
  );
}
