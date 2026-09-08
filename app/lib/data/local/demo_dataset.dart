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
///
/// Los identificadores de aquí —`p-demo-01`— **no son UUID a propósito**: se
/// leen, y así se distingue de un vistazo lo inventado de lo capturado. La
/// contrapartida es que el servidor los rechazaría, y por eso la cola de envío
/// tiene que dejarlos fuera. Que no se puedan sincronizar es la propiedad que
/// se quiere, no un descuido.
class Demo {
  const Demo._();

  static const pacientes = <DemoPaciente>[
    // Weaning difícil: tres cribados, dos intentos de PVE, el segundo todavía
    // en borrador. Es el caso que un modelo por calendario no sabe representar.
    DemoPaciente(
      id: 'p-demo-01',
      correlativo: 1,
      nombre: 'Reinaldo Estévez Cruz',
      hc: 'DEMO-01',
      telefono: '5 000 0001',
      edad: 68,
      sexo: Sexo.masculino,
      institucion: Seed.coordinador,
      protocolo: Protocolo.a,
      recolectorId: 'u-001',
      diasDesdeEnrolamiento: 6,
      sync: SyncStatus.enCola,
      eventos: [
        DemoEvento(TipoEvento.enrolamiento, 0, {
          'fecha_ingreso_uci': '2026-08-12',
          'fecha_inicio_vmi': '2026-08-14',
          'causa_intubacion': 'EPOC exacerbada',
          'via_aerea_dificil': false,
          'tot_menor_igual_65': true,
          'peso': 88,
          'talla': 1.72,
          'imc': 29.7,
          'categoria_imc': 'Sobrepeso',
          'factor_edad': true,
          'factor_obesidad': false,
          'factor_epoc': true,
          'factor_insuficiencia_cardiaca': false,
          'factor_via_aerea': true,
          'estratificacion_riesgo': 'Moderado',
          'comorbilidades': ['EPOC', 'HTA'],
        }),
        DemoEvento(TipoEvento.cribado, 2, {'cumple_criterios': false}),
        DemoEvento(TipoEvento.cribado, 3, {'cumple_criterios': false}),
        DemoEvento(TipoEvento.cribado, 4, {'cumple_criterios': true}),
        DemoEvento(TipoEvento.pruebaVentilacionEspontanea, 5, {
          'modo_ventilatorio_previo': 'PS',
          'metodo_pve': 'Tubo en T',
          'duracion_pve': 'Menos de 30 min',
          'resultado_pve': 'Fallo',
          'causa_fallo_pve': 'Secreciones abundantes o tos ineficaz',
        }),
        // Borrador abierto: el segundo intento se está capturando ahora mismo.
        DemoEvento(
          TipoEvento.pruebaVentilacionEspontanea,
          6,
          {
            'modo_ventilatorio_previo': 'PS',
            'metodo_pve': 'PSV + PEEP',
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
          {
            'fecha_ingreso_uci': '2026-08-18',
            'causa_intubacion': 'Neurológica',
          },
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
          'fecha_inicio_vmi': '2026-08-08',
          'causa_intubacion': 'Anestésica o quirúrgica',
          'via_aerea_dificil': false,
          'tot_menor_igual_65': false,
          'peso': 61,
          'talla': 1.63,
          'imc': 23.0,
          'categoria_imc': 'Normopeso',
          'factor_edad': false,
          'factor_obesidad': false,
          'factor_epoc': false,
          'factor_insuficiencia_cardiaca': false,
          'factor_via_aerea': false,
          'estratificacion_riesgo': 'Bajo',
        }),
        DemoEvento(TipoEvento.cribado, 2, {'cumple_criterios': true}),
        DemoEvento(TipoEvento.pruebaVentilacionEspontanea, 2, {
          'modo_ventilatorio_previo': 'PS',
          'metodo_pve': 'PSV',
          'duracion_pve': 'De 30 a 59 min',
          'resultado_pve': 'Éxito',
        }),
        DemoEvento(TipoEvento.extubacion, 3, {
          'traqueostomia': false,
          'modo_ventilatorio_previo_extubacion': 'CPAP',
          'test_fuga': true,
          'resultado_test_fuga': 'Con fuga',
          'esteroides_iv_previos': false,
          'tiempo_pve_extubacion': 'De 1 a 3 horas',
          'soporte_post_extubacion': true,
          'tipo_soporte': 'CNAF',
          'tiempo_soporte': 'De 24 a 47 h',
          'duracion_total_vmi': '5 días o menos',
        }),
        DemoEvento(
          TipoEvento.desenlaces,
          6,
          {
            'eventos_adversos': ['Ninguno'],
            'reintubacion_72h': false,
            'estancia_uci': 'De 6 a 14 días',
            'estado_egreso': 'Vivo',
            'fecha_egreso_uci': '2026-08-14',
          },
          recolectorId: 'u-003',
        ),
        DemoEvento(
          TipoEvento.seguimientoPostEgreso,
          13,
          {
            'ventana_contacto': 'Día 7 tras el egreso',
            'fallecido': false,
          },
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
      edad: 71,
      sexo: Sexo.masculino,
      institucion: Seed.cardiologia,
      protocolo: Protocolo.b,
      recolectorId: 'u-007',
      diasDesdeEnrolamiento: 9,
      sync: SyncStatus.sincronizado,
      eventos: [
        DemoEvento(TipoEvento.enrolamiento, 0, {
          'fecha_ingreso_uci': '2026-08-09',
          'fecha_inicio_vmi': '2026-08-11',
          'causa_intubacion': 'Insuficiencia cardíaca',
          'via_aerea_dificil': true,
          'tot_menor_igual_65': true,
          'peso': 104,
          'talla': 1.70,
          'imc': 36.0,
          'categoria_imc': 'Obeso',
          'factor_edad': true,
          'factor_obesidad': true,
          'factor_epoc': false,
          'factor_insuficiencia_cardiaca': true,
          'factor_via_aerea': true,
          'estratificacion_riesgo': 'Alto',
          'comorbilidades': ['HTA', 'IC', 'DM'],
        }),
        DemoEvento(TipoEvento.cribado, 3, {'cumple_criterios': true},
            recolectorId: 'u-002'),
        DemoEvento(
          TipoEvento.pruebaVentilacionEspontanea,
          4,
          {
            'modo_ventilatorio_previo': 'SIMV + PS',
            'metodo_pve': 'CPAP',
            'duracion_pve': 'De 60 a 119 min',
            'resultado_pve': 'Éxito',
          },
          recolectorId: 'u-002',
        ),
        DemoEvento(TipoEvento.extubacion, 4, recolectorId: 'u-002', {
          'traqueostomia': false,
          'modo_ventilatorio_previo_extubacion': 'CPAP',
          'test_fuga': false,
          'esteroides_iv_previos': true,
          'tiempo_pve_extubacion': 'Menos de 1 hora',
          'soporte_post_extubacion': true,
          'tipo_soporte': 'VNI + CNAF',
          'tiempo_soporte': 'Menos de 24 h',
          'duracion_total_vmi': '5 días o menos',
        }),
        DemoEvento(
          TipoEvento.desenlaces,
          6,
          {
            'eventos_adversos': ['Fallo respiratorio agudo'],
            'reintubacion_72h': true,
            'causa_reintubacion': 'Fallo respiratorio agudo',
            'estancia_uci': 'De 6 a 14 días',
            'estado_egreso': 'Vivo',
            'fecha_egreso_uci': '2026-08-18',
          },
          recolectorId: 'u-003',
        ),
      ],
    ),

    // Traqueostomía: la trayectoria se desvía y no llega a extubación.
    DemoPaciente(
      id: 'p-demo-05',
      correlativo: 1,
      nombre: 'Osvaldo Prieto Nodal',
      hc: 'DEMO-05',
      telefono: '5 000 0005',
      edad: 59,
      sexo: Sexo.masculino,
      institucion: Seed.militar,
      protocolo: Protocolo.a,
      recolectorId: 'u-005',
      diasDesdeEnrolamiento: 15,
      sync: SyncStatus.sincronizado,
      eventos: [
        DemoEvento(TipoEvento.enrolamiento, 0, {
          'fecha_ingreso_uci': '2026-08-03',
          'fecha_inicio_vmi': '2026-08-05',
          'causa_intubacion': 'Politrauma',
          'via_aerea_dificil': true,
          'tot_menor_igual_65': false,
          'peso': 74,
          'talla': 1.78,
          'imc': 23.4,
          'categoria_imc': 'Normopeso',
          'factor_edad': false,
          'factor_obesidad': false,
          'factor_epoc': false,
          'factor_insuficiencia_cardiaca': false,
          'factor_via_aerea': true,
          'estratificacion_riesgo': 'Moderado',
        }),
        DemoEvento(TipoEvento.cribado, 4, {'cumple_criterios': false}),
        DemoEvento(TipoEvento.cribado, 6, {'cumple_criterios': true}),
        DemoEvento(TipoEvento.pruebaVentilacionEspontanea, 7, {
          'modo_ventilatorio_previo': 'SIMV',
          'metodo_pve': 'Tubo en T',
          'duracion_pve': 'Menos de 30 min',
          'resultado_pve': 'Fallo',
          'causa_fallo_pve': 'Debilidad muscular (PIM o NIF)',
        }),
        DemoEvento(TipoEvento.pruebaVentilacionEspontanea, 9, {
          'modo_ventilatorio_previo': 'PS',
          'metodo_pve': 'PSV + PEEP',
          'duracion_pve': 'De 30 a 59 min',
          'resultado_pve': 'Fallo',
          'causa_fallo_pve': 'Disfunción diafragmática por ecografía',
        }),
        // Sin extubación: el destete siguió por traqueostomía.
        DemoEvento(TipoEvento.extubacion, 11, {
          'traqueostomia': true,
          'fecha_traqueostomia': '2026-08-16',
          'duracion_total_vmi': 'De 6 a 14 días',
        }),
      ],
    ),

    // En curso, con dos cribados registrados.
    DemoPaciente(
      id: 'p-demo-06',
      correlativo: 4,
      nombre: 'Caridad Villalón Mesa',
      hc: 'DEMO-06',
      telefono: '5 000 0006',
      edad: 63,
      sexo: Sexo.femenino,
      institucion: Seed.coordinador,
      protocolo: Protocolo.b,
      recolectorId: 'u-001',
      diasDesdeEnrolamiento: 3,
      sync: SyncStatus.local,
      eventos: [
        DemoEvento(TipoEvento.enrolamiento, 0, {
          'fecha_ingreso_uci': '2026-08-15',
          'fecha_inicio_vmi': '2026-08-17',
          'causa_intubacion': 'Respiratoria (otras causas)',
          'via_aerea_dificil': false,
          'tot_menor_igual_65': false,
          'peso': 58,
          'talla': 1.55,
          'imc': 24.1,
          'categoria_imc': 'Normopeso',
          'factor_edad': false,
          'factor_obesidad': false,
          'factor_epoc': false,
          'factor_insuficiencia_cardiaca': false,
          'factor_via_aerea': false,
          'estratificacion_riesgo': 'Bajo',
          'comorbilidades': ['AB'],
        }),
        DemoEvento(TipoEvento.cribado, 2, {'cumple_criterios': false}),
        DemoEvento(TipoEvento.cribado, 3, {'cumple_criterios': false}),
      ],
    ),

    // Trayectoria completa, con los tres contactos de seguimiento.
    DemoPaciente(
      id: 'p-demo-07',
      correlativo: 2,
      nombre: 'Ernesto Cabrera Lima',
      hc: 'DEMO-07',
      telefono: '5 000 0007',
      edad: 44,
      sexo: Sexo.masculino,
      institucion: Seed.militar,
      protocolo: Protocolo.b,
      recolectorId: 'u-005',
      diasDesdeEnrolamiento: 34,
      sync: SyncStatus.sincronizado,
      eventos: [
        DemoEvento(TipoEvento.enrolamiento, 0, {
          'fecha_ingreso_uci': '2026-07-15',
          'fecha_inicio_vmi': '2026-07-17',
          'causa_intubacion': 'Metabólica',
          'via_aerea_dificil': false,
          'tot_menor_igual_65': false,
          'peso': 70,
          'talla': 1.75,
          'imc': 22.9,
          'categoria_imc': 'Normopeso',
          'factor_edad': false,
          'factor_obesidad': false,
          'factor_epoc': false,
          'factor_insuficiencia_cardiaca': false,
          'factor_via_aerea': false,
          'estratificacion_riesgo': 'Bajo',
        }),
        DemoEvento(TipoEvento.cribado, 2, {'cumple_criterios': true}),
        DemoEvento(TipoEvento.pruebaVentilacionEspontanea, 2, {
          'modo_ventilatorio_previo': 'CPAP',
          'metodo_pve': 'CPAP',
          'duracion_pve': '120 min o más',
          'resultado_pve': 'Éxito',
        }),
        DemoEvento(TipoEvento.extubacion, 3, {
          'traqueostomia': false,
          'modo_ventilatorio_previo_extubacion': 'CPAP',
          'test_fuga': true,
          'resultado_test_fuga': 'Con fuga',
          'esteroides_iv_previos': false,
          'tiempo_pve_extubacion': 'De 4 a 11 horas',
          'soporte_post_extubacion': false,
          'duracion_total_vmi': '5 días o menos',
        }),
        DemoEvento(
          TipoEvento.desenlaces,
          5,
          {
            'eventos_adversos': ['Ninguno'],
            'reintubacion_72h': false,
            'estancia_uci': '5 días o menos',
            'estado_egreso': 'Vivo',
            'fecha_egreso_uci': '2026-07-22',
          },
          recolectorId: 'u-003',
        ),
        DemoEvento(
          TipoEvento.seguimientoPostEgreso,
          12,
          {'ventana_contacto': 'Día 7 tras el egreso', 'fallecido': false},
          recolectorId: 'u-003',
        ),
        DemoEvento(
          TipoEvento.seguimientoPostEgreso,
          19,
          {'ventana_contacto': 'Día 14 tras el egreso', 'fallecido': false},
          recolectorId: 'u-003',
        ),
        DemoEvento(
          TipoEvento.seguimientoPostEgreso,
          33,
          {'ventana_contacto': 'Día 28 tras el egreso', 'fallecido': false},
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
      campo: 'causa_fallo_pve',
      valorAnterior: 'Asincronías',
      valorNuevo: 'Secreciones abundantes o tos ineficaz',
      motivo: 'precisado tras revisar la hoja de enfermería',
    ),
    DemoAuditoria(
      ocurridoEn: DateTime(2026, 8, 19, 16, 40),
      autor: Seed.principal,
      pacienteId: 'p-demo-04',
      tipo: TipoEvento.desenlaces,
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
      valorAnterior: 'De 6 a 14 días',
      valorNuevo: '5 días o menos',
      motivo: 'se contaron días de ingreso, no de ventilación',
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
