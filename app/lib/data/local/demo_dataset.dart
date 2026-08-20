import '../../domain/models/evento_clinico.dart';
import '../../domain/models/institucion.dart';
import '../../domain/models/patient.dart';
import '../../domain/models/protocolo.dart';
import '../../domain/models/role.dart';
import 'seed_data.dart';

/// Juego de datos de demostración.
///
/// **Ningún paciente de aquí es real.** Son trayectorias inventadas, elegidas
/// para que se vea lo que el modelo por eventos permite y el de calendario no:
/// hitos que se repiten un número distinto de veces en cada paciente, y
/// trayectorias que terminan donde la clínica las termina.
///
/// Los desenlaces los captura el evaluador y no quien aplicó el protocolo:
/// es la separación de funciones del ensayo, y conviene que la demostración la
/// refleje (BASES §4).
class Demo {
  const Demo._();

  static const pacientes = <DemoPaciente>[
    // Weaning difícil: tres días de cribado, dos intentos de PVE, el segundo
    // todavía en borrador. Es el caso que el modelo anterior no podía
    // representar.
    DemoPaciente(
      id: 'p-demo-01',
      correlativo: 1,
      nombre: 'Reinaldo Estévez Cruz',
      hc: 'DEMO-01',
      telefono: '5 000 0001',
      edad: 62,
      sexo: Sexo.masculino,
      institucion: Seed.coordinador,
      protocolo: Protocolo.a,
      recolectorId: 'u-001',
      diasDesdeEnrolamiento: 6,
      sync: SyncStatus.enCola,
      eventos: [
        DemoEvento(TipoEvento.enrolamiento, 0, {
          'fecha_ingreso_uci': '2026-08-12',
          'imc': '25–29,9 · sobrepeso',
          'causa_intubacion': 'Respiratoria',
          'comorbilidades': ['EPOC', 'HTA'],
        }),
        DemoEvento(TipoEvento.estratificacionRiesgo, 0, {
          'fecha_inicio_vmi': '2026-08-14',
          'fecha_primera_evaluacion': '2026-08-14',
          'fio2': 55,
          'peep': 8,
        }),
        DemoEvento(TipoEvento.cribado, 2, {
          'cumple_criterios': false,
          'observaciones': 'Persiste requerimiento de FiO₂ elevada.',
        }),
        DemoEvento(TipoEvento.cribado, 3, {
          'cumple_criterios': false,
          'observaciones': 'Mejora ventilatoria, aún sin criterios completos.',
        }),
        DemoEvento(TipoEvento.cribado, 4, {'cumple_criterios': true}),
        DemoEvento(TipoEvento.evaluacionDiaria, 5, {
          'detencion_sedacion': true,
          'duracion_detencion_sedacion': 4,
          'evaluacion_ventilacion_espontanea': true,
          'duracion_ventilacion_espontanea': '> 15 min',
        }),
        DemoEvento(TipoEvento.pruebaVentilacionEspontanea, 5, {
          'metodo_pve': 'Tubo en T',
          'rsbi_inicio': '≤ 105',
          'fr_inicio': 24,
          'vt_inicio': 380,
          'vm_inicio': 9.1,
          'rsbi_final': '> 105',
          'fr_final': 34,
          'vt_final': 290,
          'vm_final': 9.9,
          'resultado_pve': 'Fallo',
          'duracion_pve': '< 30 min',
        }),
        // Borrador abierto: el segundo intento se está capturando ahora mismo.
        DemoEvento(
          TipoEvento.pruebaVentilacionEspontanea,
          6,
          {
            'metodo_pve': 'PSV + PEEP',
            'rsbi_inicio': '≤ 105',
            'fr_inicio': 21,
          },
          borrador: true,
        ),
      ],
    ),

    // Recién enrolado, con el enrolamiento aún en borrador.
    DemoPaciente(
      id: 'p-demo-02',
      correlativo: 2,
      nombre: 'Marta Ojeda Pino',
      hc: 'DEMO-02',
      telefono: '5 000 0002',
      edad: 54,
      sexo: Sexo.femenino,
      institucion: Seed.coordinador,
      protocolo: Protocolo.b,
      recolectorId: 'u-001',
      diasDesdeEnrolamiento: 0,
      sync: SyncStatus.enCola,
      eventos: [
        DemoEvento(
          TipoEvento.enrolamiento,
          0,
          {'fecha_ingreso_uci': '2026-08-18', 'causa_intubacion': 'Neurológica'},
          borrador: true,
        ),
      ],
    ),

    // Weaning simple: un cribado, una PVE, extubación y alta viva.
    DemoPaciente(
      id: 'p-demo-03',
      correlativo: 3,
      nombre: 'Yanet Fuentes Abreu',
      hc: 'DEMO-03',
      telefono: '5 000 0003',
      edad: 47,
      sexo: Sexo.femenino,
      institucion: Seed.coordinador,
      protocolo: Protocolo.a,
      recolectorId: 'u-001',
      diasDesdeEnrolamiento: 12,
      sync: SyncStatus.sincronizado,
      eventos: [
        DemoEvento(TipoEvento.enrolamiento, 0, {
          'fecha_ingreso_uci': '2026-08-06',
          'imc': '18,5–24,9 · normopeso',
          'causa_intubacion': 'Anestésica/quirúrgica',
        }),
        DemoEvento(TipoEvento.estratificacionRiesgo, 0, {
          'fecha_inicio_vmi': '2026-08-08',
          'fecha_primera_evaluacion': '2026-08-08',
          'fio2': 40,
          'peep': 5,
        }),
        DemoEvento(TipoEvento.cribado, 2, {'cumple_criterios': true}),
        DemoEvento(TipoEvento.evaluacionDiaria, 2, {
          'detencion_sedacion': true,
          'duracion_detencion_sedacion': 6,
          'evaluacion_ventilacion_espontanea': true,
          'duracion_ventilacion_espontanea': '> 15 min',
        }),
        DemoEvento(TipoEvento.pruebaVentilacionEspontanea, 2, {
          'metodo_pve': 'PSV',
          'rsbi_inicio': '≤ 58',
          'fr_inicio': 18,
          'vt_inicio': 460,
          'rsbi_final': '≤ 58',
          'fr_final': 19,
          'vt_final': 450,
          'resultado_pve': 'Éxito',
          'duracion_pve': '30–60 min',
        }),
        DemoEvento(TipoEvento.extubacion, 3, {
          'test_fuga': true,
          'resultado_test_fuga': 'Con fuga',
          'fecha_pve_exitosa': '2026-08-10',
          'tiempo_pve_extubacion': 2,
          'duracion_total_vmi': 4,
        }),
        DemoEvento(TipoEvento.soportePostExtubacion, 3, {
          'soporte_post_extubacion': true,
          'tipo_soporte': 'HFNC',
        }),
        DemoEvento(
          TipoEvento.reintubacion,
          6,
          {
            'reintubacion_72h': false,
            'eventos_adversos': ['Ninguna'],
          },
          recolectorId: 'u-003',
        ),
        DemoEvento(
          TipoEvento.egresoUci,
          8,
          {'estancia_uci': 10, 'estado_egreso': 'Vivo'},
          recolectorId: 'u-003',
        ),
      ],
    ),

    // Extubación fallida: el desenlace principal del ensayo.
    DemoPaciente(
      id: 'p-demo-04',
      correlativo: 1,
      nombre: 'Idalberto Sáez Roque',
      hc: 'DEMO-04',
      telefono: '5 000 0004',
      edad: 58,
      sexo: Sexo.masculino,
      institucion: Seed.cardiologia,
      protocolo: Protocolo.a,
      recolectorId: 'u-002',
      diasDesdeEnrolamiento: 20,
      sync: SyncStatus.sincronizado,
      eventos: [
        DemoEvento(
          TipoEvento.enrolamiento,
          0,
          {
            'fecha_ingreso_uci': '2026-07-29',
            'causa_intubacion': 'Shock',
            'comorbilidades': ['DM', 'ERC'],
          },
          recolectorId: 'u-007',
        ),
        DemoEvento(TipoEvento.estratificacionRiesgo, 0, {
          'fecha_inicio_vmi': '2026-07-31',
          'fecha_primera_evaluacion': '2026-07-31',
          'fio2': 60,
          'peep': 10,
        }),
        DemoEvento(TipoEvento.cribado, 3, {'cumple_criterios': true}),
        DemoEvento(TipoEvento.evaluacionDiaria, 3, {
          'detencion_sedacion': true,
          'duracion_detencion_sedacion': 2,
          'evaluacion_ventilacion_espontanea': true,
          'duracion_ventilacion_espontanea': '10–15 min',
        }),
        DemoEvento(TipoEvento.pruebaVentilacionEspontanea, 4, {
          'metodo_pve': 'CPAP',
          'rsbi_inicio': '≤ 105',
          'fr_inicio': 26,
          'pplateau_inicio': 22,
          'driving_pressure_inicio': 13,
          'rsbi_final': '≤ 105',
          'fr_final': 28,
          'resultado_pve': 'Éxito',
          'duracion_pve': '60–120 min',
        }),
        DemoEvento(TipoEvento.extubacion, 4, {
          'test_fuga': false,
          'fecha_pve_exitosa': '2026-08-03',
          'duracion_total_vmi': 6,
        }),
        DemoEvento(TipoEvento.soportePostExtubacion, 4, {
          'soporte_post_extubacion': true,
          'tipo_soporte': 'VNI',
        }),
        DemoEvento(
          TipoEvento.reintubacion,
          6,
          {
            'reintubacion_72h': true,
            'causa_reintubacion': 'Fallo respiratorio agudo',
            'eventos_adversos': ['Fallo respiratorio agudo'],
          },
          recolectorId: 'u-003',
        ),
        DemoEvento(
          TipoEvento.egresoUci,
          18,
          {'estancia_uci': 21, 'estado_egreso': 'Vivo'},
          recolectorId: 'u-003',
        ),
      ],
    ),

    // Traqueostomía: la trayectoria se desvía y no llega a extubación.
    DemoPaciente(
      id: 'p-demo-05',
      correlativo: 2,
      nombre: 'Caridad Nápoles Vega',
      hc: 'DEMO-05',
      telefono: '5 000 0005',
      edad: 71,
      sexo: Sexo.femenino,
      institucion: Seed.cardiologia,
      protocolo: Protocolo.b,
      recolectorId: 'u-002',
      diasDesdeEnrolamiento: 16,
      sync: SyncStatus.sincronizado,
      eventos: [
        DemoEvento(
          TipoEvento.enrolamiento,
          0,
          {
            'fecha_ingreso_uci': '2026-08-02',
            'causa_intubacion': 'Neurológica',
            'comorbilidades': ['HTA', 'ECV previa'],
          },
          recolectorId: 'u-007',
        ),
        DemoEvento(TipoEvento.estratificacionRiesgo, 0, {
          'fecha_inicio_vmi': '2026-08-04',
          'fecha_primera_evaluacion': '2026-08-04',
          'fio2': 45,
          'peep': 8,
        }),
        DemoEvento(TipoEvento.cribado, 2, {'cumple_criterios': false}),
        DemoEvento(TipoEvento.cribado, 3, {'cumple_criterios': false}),
        DemoEvento(TipoEvento.cribado, 4, {'cumple_criterios': false}),
        DemoEvento(TipoEvento.cribado, 5, {
          'cumple_criterios': false,
          'observaciones': 'Sin progreso neurológico. Se plantea traqueostomía.',
        }),
        DemoEvento(TipoEvento.traqueostomia, 7, {
          'observaciones': 'Percutánea, sin incidencias.',
        }),
      ],
    ),

    // En curso, con dos cribados registrados.
    DemoPaciente(
      id: 'p-demo-06',
      correlativo: 4,
      nombre: 'Osvaldo Prieto Lima',
      hc: 'DEMO-06',
      telefono: '5 000 0006',
      edad: 69,
      sexo: Sexo.masculino,
      institucion: Seed.coordinador,
      protocolo: Protocolo.b,
      recolectorId: 'u-001',
      diasDesdeEnrolamiento: 3,
      sync: SyncStatus.sincronizado,
      eventos: [
        DemoEvento(TipoEvento.enrolamiento, 0, {
          'fecha_ingreso_uci': '2026-08-15',
          'causa_intubacion': 'Cardiovascular',
          'comorbilidades': ['CI', 'IC'],
        }),
        DemoEvento(TipoEvento.estratificacionRiesgo, 0, {
          'fecha_inicio_vmi': '2026-08-17',
          'fecha_primera_evaluacion': '2026-08-17',
          'fio2': 50,
          'peep': 6,
        }),
        DemoEvento(TipoEvento.cribado, 2, {'cumple_criterios': false}),
        DemoEvento(TipoEvento.cribado, 3, {'cumple_criterios': false}),
      ],
    ),

    // Trayectoria completa con seguimiento post-egreso.
    DemoPaciente(
      id: 'p-demo-07',
      correlativo: 3,
      nombre: 'Elsa Camacho Ruiz',
      hc: 'DEMO-07',
      telefono: '5 000 0007',
      edad: 44,
      sexo: Sexo.femenino,
      institucion: Seed.cardiologia,
      protocolo: Protocolo.a,
      recolectorId: 'u-002',
      diasDesdeEnrolamiento: 34,
      sync: SyncStatus.sincronizado,
      eventos: [
        DemoEvento(
          TipoEvento.enrolamiento,
          0,
          {
            'fecha_ingreso_uci': '2026-07-15',
            'imc': '30–39,9 · obeso',
            'causa_intubacion': 'Respiratoria',
          },
          recolectorId: 'u-007',
        ),
        DemoEvento(TipoEvento.estratificacionRiesgo, 0, {
          'fecha_inicio_vmi': '2026-07-17',
          'fecha_primera_evaluacion': '2026-07-17',
          'fio2': 65,
          'peep': 12,
        }),
        DemoEvento(TipoEvento.cribado, 3, {'cumple_criterios': true}),
        DemoEvento(TipoEvento.evaluacionDiaria, 3, {
          'detencion_sedacion': true,
          'duracion_detencion_sedacion': 5,
          'evaluacion_ventilacion_espontanea': true,
          'duracion_ventilacion_espontanea': '> 15 min',
        }),
        DemoEvento(TipoEvento.pruebaVentilacionEspontanea, 4, {
          'metodo_pve': 'PSV + PEEP',
          'rsbi_inicio': '≤ 58',
          'fr_inicio': 20,
          'resultado_pve': 'Éxito',
          'duracion_pve': '30–60 min',
        }),
        DemoEvento(TipoEvento.extubacion, 4, {
          'test_fuga': true,
          'resultado_test_fuga': 'Sin fuga',
          'fecha_pve_exitosa': '2026-07-19',
          'duracion_total_vmi': 6,
        }),
        DemoEvento(TipoEvento.soportePostExtubacion, 4, {
          'soporte_post_extubacion': true,
          'tipo_soporte': 'VNI + HFNC',
        }),
        DemoEvento(
          TipoEvento.reintubacion,
          7,
          {
            'reintubacion_72h': false,
            'eventos_adversos': ['Estridor'],
          },
          recolectorId: 'u-003',
        ),
        DemoEvento(
          TipoEvento.egresoUci,
          9,
          {'estancia_uci': 11, 'estado_egreso': 'Vivo'},
          recolectorId: 'u-003',
        ),
        DemoEvento(
          TipoEvento.seguimientoPostEgreso,
          33,
          {'fallecimiento_post_egreso': 'No fallecimiento a 28 días'},
          recolectorId: 'u-003',
        ),
      ],
    ),
  ];

  /// Correcciones de muestra, para que el historial de auditoría no salga vacío.
  static final auditoria = <DemoAuditoria>[
    DemoAuditoria(
      ocurridoEn: DateTime(2026, 8, 20, 8, 12),
      autor: Seed.principal,
      pacienteId: 'p-demo-01',
      tipo: TipoEvento.pruebaVentilacionEspontanea,
      ocurrencia: 1,
      campo: 'vt_final',
      valorAnterior: '920',
      valorNuevo: '290',
      motivo: 'cifras transpuestas al teclear',
    ),
    DemoAuditoria(
      ocurridoEn: DateTime(2026, 8, 19, 16, 40),
      autor: Seed.principal,
      pacienteId: 'p-demo-04',
      tipo: TipoEvento.reintubacion,
      ocurrencia: 1,
      campo: 'causa_reintubacion',
      valorAnterior: 'Otra',
      valorNuevo: 'Fallo respiratorio agudo',
      motivo: 'precisado tras revisar la historia clínica',
    ),
    DemoAuditoria(
      ocurridoEn: DateTime(2026, 8, 18, 9, 22),
      autor: Seed.principal,
      pacienteId: 'p-demo-03',
      tipo: TipoEvento.extubacion,
      ocurrencia: 1,
      campo: 'duracion_total_vmi',
      valorAnterior: '40',
      valorNuevo: '4',
      motivo: 'cero de más',
    ),
  ];

  static DemoPaciente porId(String id) =>
      pacientes.firstWhere((p) => p.id == id);
}

class DemoPaciente {
  const DemoPaciente({
    required this.id,
    required this.correlativo,
    required this.nombre,
    required this.hc,
    required this.telefono,
    required this.edad,
    required this.sexo,
    required this.institucion,
    required this.protocolo,
    required this.recolectorId,
    required this.diasDesdeEnrolamiento,
    required this.sync,
    required this.eventos,
  });

  final String id;

  /// Correlativo dentro de su centro. El código sale de aquí.
  final int correlativo;
  final String nombre;
  final String hc;
  final String telefono;
  final int edad;
  final Sexo sexo;
  final Institucion institucion;
  final Protocolo protocolo;
  final String recolectorId;

  /// Cuántos días antes de [Seed.hoy] se enroló.
  final int diasDesdeEnrolamiento;
  final SyncStatus sync;
  final List<DemoEvento> eventos;

  String get codigo =>
      '${institucion.codigo}-${correlativo.toString().padLeft(3, '0')}';

  DateTime get enroladoEn =>
      Seed.hoy.subtract(Duration(days: diasDesdeEnrolamiento));

  String get apellidos {
    final partes = nombre.split(' ');
    return partes.length <= 2 ? nombre : partes.sublist(1).join(' ');
  }
}

class DemoEvento {
  const DemoEvento(
    this.tipo,
    this.diaDesdeEnrolamiento,
    this.valores, {
    this.borrador = false,
    this.recolectorId,
  });

  final TipoEvento tipo;

  /// Días transcurridos desde el enrolamiento hasta que ocurrió el hito.
  final int diaDesdeEnrolamiento;
  final Map<String, Object?> valores;
  final bool borrador;

  /// Quién lo capturó, si no fue el recolector habitual del paciente. Los
  /// desenlaces los registra el evaluador, no quien aplicó el protocolo.
  final String? recolectorId;
}

class DemoAuditoria {
  const DemoAuditoria({
    required this.ocurridoEn,
    required this.autor,
    required this.pacienteId,
    required this.tipo,
    required this.ocurrencia,
    required this.campo,
    required this.valorAnterior,
    required this.valorNuevo,
    required this.motivo,
  });

  final DateTime ocurridoEn;
  final Investigador autor;
  final String pacienteId;
  final TipoEvento tipo;
  final int ocurrencia;
  final String campo;
  final String? valorAnterior;
  final String? valorNuevo;
  final String motivo;
}
