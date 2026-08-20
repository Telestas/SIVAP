import '../../domain/models/evento_clinico.dart';
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
/// Vive aparte de las implementaciones de almacén para que la versión en
/// memoria y la de SQLite muestren exactamente lo mismo.
class Demo {
  const Demo._();

  static const pacientes = <DemoPaciente>[
    // Weaning difícil: tres días de cribado, dos intentos de PVE, el segundo
    // todavía en borrador. Es el caso que el modelo anterior no podía
    // representar.
    DemoPaciente(
      id: 'p-demo-01',
      nombre: 'Reinaldo Estévez Cruz',
      carneIdentidad: '00000000001',
      edad: 62,
      sexo: Sexo.masculino,
      hc: 'DEMO-01',
      telefono: '5 000 0001',
      protocolo: Protocolo.a,
      recolectorId: 'u-001',
      diasDesdeEnrolamiento: 6,
      sync: SyncStatus.enCola,
      eventos: [
        DemoEvento(TipoEvento.enrolamiento, 0, {
          'fecha_ingreso_uci': '2026-08-12',
          'causa_intubacion': 'Respiratoria',
          'comorbilidades': ['EPOC', 'HTA'],
          'imc': '25–29,9 sobrepeso',
        }),
        DemoEvento(TipoEvento.estratificacionRiesgo, 0, {
          'fecha_inicio_vmi': '2026-08-14',
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
          'evaluacion_ventilacion_espontanea': true,
          'duracion_ventilacion_espontanea': '> 15 min',
        }),
        DemoEvento(TipoEvento.pruebaVentilacionEspontanea, 5, {
          'metodo_pve': 'Tubo en T',
          'rsbi_inicio': 88,
          'fr_inicio': 24,
          'rsbi_final': 118,
          'fr_final': 34,
          'resultado_pve': 'Fallo',
          'duracion_pve': '< 30 min',
        }),
        // Borrador abierto: el segundo intento se está capturando ahora mismo.
        DemoEvento(
          TipoEvento.pruebaVentilacionEspontanea,
          6,
          {'metodo_pve': 'PSV + PEEP', 'rsbi_inicio': 74, 'fr_inicio': 21},
          borrador: true,
        ),
      ],
    ),

    // Recién enrolado, con el enrolamiento aún en borrador.
    DemoPaciente(
      id: 'p-demo-02',
      nombre: 'Marta Ojeda Pino',
      carneIdentidad: '00000000002',
      edad: 54,
      sexo: Sexo.femenino,
      hc: 'DEMO-02',
      telefono: '5 000 0002',
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
      nombre: 'Yanet Fuentes Abreu',
      carneIdentidad: '00000000003',
      edad: 47,
      sexo: Sexo.femenino,
      hc: 'DEMO-03',
      telefono: '5 000 0003',
      protocolo: Protocolo.a,
      recolectorId: 'u-001',
      diasDesdeEnrolamiento: 12,
      sync: SyncStatus.sincronizado,
      eventos: [
        DemoEvento(TipoEvento.enrolamiento, 0, {
          'fecha_ingreso_uci': '2026-08-06',
          'causa_intubacion': 'Anestésica/quirúrgica',
          'imc': '18,5–24,9 normopeso',
        }),
        DemoEvento(TipoEvento.estratificacionRiesgo, 0,
            {'fecha_inicio_vmi': '2026-08-08', 'fio2': 40, 'peep': 5}),
        DemoEvento(TipoEvento.cribado, 2, {'cumple_criterios': true}),
        DemoEvento(TipoEvento.evaluacionDiaria, 2, {
          'detencion_sedacion': true,
          'evaluacion_ventilacion_espontanea': true,
          'duracion_ventilacion_espontanea': '> 15 min',
        }),
        DemoEvento(TipoEvento.pruebaVentilacionEspontanea, 2, {
          'metodo_pve': 'PSV',
          'rsbi_inicio': 52,
          'fr_inicio': 18,
          'rsbi_final': 56,
          'fr_final': 19,
          'resultado_pve': 'Éxito',
          'duracion_pve': '30–60 min',
        }),
        DemoEvento(TipoEvento.extubacion, 3, {
          'test_fuga': true,
          'resultado_test_fuga': 'Con fuga',
          'duracion_total_vmi': 4,
        }),
        DemoEvento(TipoEvento.soportePostExtubacion, 3, {'tipo_soporte': 'HFNC'}),
        DemoEvento(TipoEvento.egresoUci, 8,
            {'estancia_uci': 10, 'estado_egreso': 'Vivo'}),
      ],
    ),

    // Extubación fallida: el desenlace principal del ensayo.
    DemoPaciente(
      id: 'p-demo-04',
      nombre: 'Idalberto Sáez Roque',
      carneIdentidad: '00000000004',
      edad: 58,
      sexo: Sexo.masculino,
      hc: 'DEMO-04',
      telefono: '5 000 0004',
      protocolo: Protocolo.a,
      recolectorId: 'u-002',
      diasDesdeEnrolamiento: 20,
      sync: SyncStatus.sincronizado,
      eventos: [
        DemoEvento(TipoEvento.enrolamiento, 0, {
          'fecha_ingreso_uci': '2026-07-29',
          'causa_intubacion': 'Shock',
          'comorbilidades': ['DM', 'ERC'],
        }),
        DemoEvento(TipoEvento.estratificacionRiesgo, 0,
            {'fecha_inicio_vmi': '2026-07-31', 'fio2': 60, 'peep': 10}),
        DemoEvento(TipoEvento.cribado, 3, {'cumple_criterios': true}),
        DemoEvento(TipoEvento.evaluacionDiaria, 3, {
          'detencion_sedacion': true,
          'evaluacion_ventilacion_espontanea': true,
          'duracion_ventilacion_espontanea': '10–15 min',
        }),
        DemoEvento(TipoEvento.pruebaVentilacionEspontanea, 4, {
          'metodo_pve': 'CPAP',
          'rsbi_inicio': 96,
          'fr_inicio': 26,
          'rsbi_final': 101,
          'fr_final': 28,
          'resultado_pve': 'Éxito',
          'duracion_pve': '60–120 min',
        }),
        DemoEvento(TipoEvento.extubacion, 4,
            {'test_fuga': false, 'duracion_total_vmi': 6}),
        DemoEvento(TipoEvento.soportePostExtubacion, 4, {'tipo_soporte': 'VNI'}),
        DemoEvento(TipoEvento.reintubacion, 6, {
          'reintubacion_72h': true,
          'causa_reintubacion': 'Fallo respiratorio agudo',
        }),
        DemoEvento(TipoEvento.egresoUci, 18,
            {'estancia_uci': 21, 'estado_egreso': 'Vivo'}),
      ],
    ),

    // Traqueostomía: la trayectoria se desvía y no llega a extubación.
    DemoPaciente(
      id: 'p-demo-05',
      nombre: 'Caridad Nápoles Vega',
      carneIdentidad: '00000000005',
      edad: 71,
      sexo: Sexo.femenino,
      hc: 'DEMO-05',
      telefono: '5 000 0005',
      protocolo: Protocolo.b,
      recolectorId: 'u-002',
      diasDesdeEnrolamiento: 16,
      sync: SyncStatus.sincronizado,
      eventos: [
        DemoEvento(TipoEvento.enrolamiento, 0, {
          'fecha_ingreso_uci': '2026-08-02',
          'causa_intubacion': 'Neurológica',
          'comorbilidades': ['HTA', 'ECV previa'],
        }),
        DemoEvento(TipoEvento.estratificacionRiesgo, 0,
            {'fecha_inicio_vmi': '2026-08-04', 'fio2': 45, 'peep': 8}),
        DemoEvento(TipoEvento.cribado, 2, {'cumple_criterios': false}),
        DemoEvento(TipoEvento.cribado, 3, {'cumple_criterios': false}),
        DemoEvento(TipoEvento.cribado, 4, {'cumple_criterios': false}),
        DemoEvento(TipoEvento.cribado, 5, {
          'cumple_criterios': false,
          'observaciones': 'Sin progreso neurológico. Se plantea traqueostomía.',
        }),
        DemoEvento(TipoEvento.traqueostomia, 7,
            {'fecha_traqueostomia': '2026-08-11'}),
      ],
    ),

    // En curso, con dos cribados registrados.
    DemoPaciente(
      id: 'p-demo-06',
      nombre: 'Osvaldo Prieto Lima',
      carneIdentidad: '00000000006',
      edad: 69,
      sexo: Sexo.masculino,
      hc: 'DEMO-06',
      telefono: '5 000 0006',
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
        DemoEvento(TipoEvento.estratificacionRiesgo, 0,
            {'fecha_inicio_vmi': '2026-08-17', 'fio2': 50, 'peep': 6}),
        DemoEvento(TipoEvento.cribado, 2, {'cumple_criterios': false}),
        DemoEvento(TipoEvento.cribado, 3, {'cumple_criterios': false}),
      ],
    ),

    // Trayectoria completa con seguimiento post-egreso.
    DemoPaciente(
      id: 'p-demo-07',
      nombre: 'Elsa Camacho Ruiz',
      carneIdentidad: '00000000007',
      edad: 44,
      sexo: Sexo.femenino,
      hc: 'DEMO-07',
      telefono: '5 000 0007',
      protocolo: Protocolo.a,
      recolectorId: 'u-002',
      diasDesdeEnrolamiento: 34,
      sync: SyncStatus.sincronizado,
      eventos: [
        DemoEvento(TipoEvento.enrolamiento, 0, {
          'fecha_ingreso_uci': '2026-07-15',
          'causa_intubacion': 'Respiratoria',
          'imc': '30–39,9 obeso',
        }),
        DemoEvento(TipoEvento.estratificacionRiesgo, 0,
            {'fecha_inicio_vmi': '2026-07-17', 'fio2': 65, 'peep': 12}),
        DemoEvento(TipoEvento.cribado, 3, {'cumple_criterios': true}),
        DemoEvento(TipoEvento.evaluacionDiaria, 3, {
          'detencion_sedacion': true,
          'evaluacion_ventilacion_espontanea': true,
          'duracion_ventilacion_espontanea': '> 15 min',
        }),
        DemoEvento(TipoEvento.pruebaVentilacionEspontanea, 4, {
          'metodo_pve': 'PSV + PEEP',
          'rsbi_inicio': 61,
          'fr_inicio': 20,
          'rsbi_final': 64,
          'fr_final': 21,
          'resultado_pve': 'Éxito',
          'duracion_pve': '30–60 min',
        }),
        DemoEvento(TipoEvento.extubacion, 4, {
          'test_fuga': true,
          'resultado_test_fuga': 'Sin fuga',
          'duracion_total_vmi': 6,
        }),
        DemoEvento(
            TipoEvento.soportePostExtubacion, 4, {'tipo_soporte': 'VNI + HFNC'}),
        DemoEvento(TipoEvento.egresoUci, 9,
            {'estancia_uci': 11, 'estado_egreso': 'Vivo'}),
        DemoEvento(TipoEvento.seguimientoPostEgreso, 33,
            {'fallecimiento_post_egreso': 'No fallecimiento a 28 días'}),
      ],
    ),
  ];

  /// Correcciones de muestra, para que el historial de auditoría no salga vacío.
  static final auditoria = <DemoAuditoria>[
    DemoAuditoria(
      ocurridoEn: DateTime(2026, 8, 20, 8, 12),
      autor: Seed.guerra,
      pacienteId: 'p-demo-01',
      tipo: TipoEvento.pruebaVentilacionEspontanea,
      ocurrencia: 1,
      campo: 'rsbi_final',
      valorAnterior: '181',
      valorNuevo: '118',
      motivo: 'cifras transpuestas al teclear',
    ),
    DemoAuditoria(
      ocurridoEn: DateTime(2026, 8, 19, 16, 40),
      autor: Seed.guerra,
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
      autor: Seed.guerra,
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
    required this.nombre,
    required this.carneIdentidad,
    required this.edad,
    required this.sexo,
    required this.hc,
    required this.telefono,
    required this.protocolo,
    required this.recolectorId,
    required this.diasDesdeEnrolamiento,
    required this.sync,
    required this.eventos,
  });

  final String id;
  final String nombre;
  final String carneIdentidad;
  final int edad;
  final Sexo sexo;
  final String hc;
  final String telefono;
  final Protocolo protocolo;
  final String recolectorId;

  /// Cuántos días antes de [Seed.hoy] se enroló.
  final int diasDesdeEnrolamiento;
  final SyncStatus sync;
  final List<DemoEvento> eventos;

  DateTime get enroladoEn =>
      Seed.hoy.subtract(Duration(days: diasDesdeEnrolamiento));

  /// Dirección de demostración. El paso 5 elimina este campo de la ficha: el
  /// Anexo 4 no lo pide, y cada dato personal de más hay que justificarlo.
  String get direccion => 'Dirección de demostración';

  String get apellidos {
    final partes = nombre.split(' ');
    return partes.length <= 2 ? nombre : partes.sublist(1).join(' ');
  }
}

class DemoEvento {
  const DemoEvento(this.tipo, this.diaDesdeEnrolamiento, this.valores,
      {this.borrador = false});

  final TipoEvento tipo;

  /// Días transcurridos desde el enrolamiento hasta que ocurrió el hito.
  final int diaDesdeEnrolamiento;
  final Map<String, Object?> valores;
  final bool borrador;
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
