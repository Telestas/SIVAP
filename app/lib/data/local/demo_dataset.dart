import '../../domain/models/audit_entry.dart';
import '../../domain/models/patient.dart';
import '../../domain/models/protocolo.dart';
import '../../domain/models/role.dart';
import '../../domain/models/visit.dart';
import 'seed_data.dart';

/// Juego de datos de demostración: los mismos casos del canvas de diseño.
///
/// Vive aparte de las implementaciones de almacén para que la versión en
/// memoria y la versión en SQLite muestren exactamente lo mismo. Dos juegos de
/// datos de prueba divergiendo es una fuente de confusión gratuita.
///
/// NINGUNO de estos pacientes es real.
class Demo {
  const Demo._();

  static const pacientes = <DemoPaciente>[
    DemoPaciente(
      id: 'p-estevez',
      nombre: 'Reinaldo Estévez Cruz',
      carneIdentidad: '64020112345',
      edad: 62,
      sexo: Sexo.masculino,
      hc: '41-2298',
      telefono: '5 218 4409',
      direccion: 'Ave. Céspedes nº 118, Rpto. Vista Alegre, mun. Santiago',
      protocolo: Protocolo.nuevo,
      recolectorId: 'u-morales',
      diasDesdeEnrolamiento: 4,
      estados: [
        VisitStatus.enviada,
        VisitStatus.enviada,
        VisitStatus.enCaptura,
        VisitStatus.programada,
        VisitStatus.programada,
      ],
      sync: SyncStatus.enCola,
    ),
    DemoPaciente(
      id: 'p-ojeda',
      nombre: 'Marta Ojeda Pino',
      carneIdentidad: '72031544218',
      edad: 54,
      sexo: Sexo.femenino,
      hc: '41-2301',
      telefono: '5 342 8871',
      direccion: 'Calle 21 e/ 4 y 6, Rpto. Sueño, mun. Santiago',
      protocolo: Protocolo.vigente,
      recolectorId: 'u-morales',
      diasDesdeEnrolamiento: 0,
      estados: [
        VisitStatus.enCaptura,
        VisitStatus.programada,
        VisitStatus.programada,
        VisitStatus.programada,
        VisitStatus.programada,
      ],
      sync: SyncStatus.enCola,
    ),
    DemoPaciente(
      id: 'p-fuentes',
      nombre: 'Yanet Fuentes Abreu',
      carneIdentidad: '79061233087',
      edad: 47,
      sexo: Sexo.femenino,
      hc: '41-2287',
      telefono: '5 471 2093',
      direccion: 'Calle 9 nº 402, Rpto. Santa Bárbara, mun. Santiago',
      protocolo: Protocolo.nuevo,
      recolectorId: 'u-morales',
      diasDesdeEnrolamiento: 6,
      estados: [
        VisitStatus.enviada,
        VisitStatus.enviada,
        VisitStatus.enviada,
        VisitStatus.programada,
        VisitStatus.programada,
      ],
      sync: SyncStatus.sincronizado,
    ),
    DemoPaciente(
      id: 'p-saez',
      nombre: 'Idalberto Sáez Roque',
      carneIdentidad: '68091877431',
      edad: 58,
      sexo: Sexo.masculino,
      hc: '41-2244',
      telefono: '5 663 5510',
      direccion: 'Carretera del Caney km 2, mun. Santiago',
      protocolo: Protocolo.nuevo,
      recolectorId: 'u-perez',
      diasDesdeEnrolamiento: 15,
      estados: [
        VisitStatus.enviada,
        VisitStatus.enviada,
        VisitStatus.enviada,
        VisitStatus.enviada,
        VisitStatus.enviada,
      ],
      sync: SyncStatus.sincronizado,
    ),
    DemoPaciente(
      id: 'p-napoles',
      nombre: 'Caridad Nápoles Vega',
      carneIdentidad: '55112000914',
      edad: 71,
      sexo: Sexo.femenino,
      hc: '41-2239',
      telefono: '5 109 7734',
      direccion: 'Calle Heredia nº 57, centro, mun. Santiago',
      protocolo: Protocolo.vigente,
      recolectorId: 'u-perez',
      diasDesdeEnrolamiento: 7,
      estados: [
        VisitStatus.enviada,
        VisitStatus.enviada,
        VisitStatus.perdida,
        VisitStatus.programada,
        VisitStatus.programada,
      ],
      sync: SyncStatus.sincronizado,
    ),
    DemoPaciente(
      id: 'p-prieto',
      nombre: 'Osvaldo Prieto Lima',
      carneIdentidad: '57042266180',
      edad: 69,
      sexo: Sexo.masculino,
      hc: '41-2270',
      telefono: '5 882 3145',
      direccion: 'Calle 6 nº 21, Rpto. Sueño, mun. Santiago',
      protocolo: Protocolo.vigente,
      recolectorId: 'u-morales',
      diasDesdeEnrolamiento: 10,
      estados: [
        VisitStatus.enviada,
        VisitStatus.enviada,
        VisitStatus.enviada,
        VisitStatus.enviada,
        VisitStatus.programada,
      ],
      sync: SyncStatus.sincronizado,
    ),
    DemoPaciente(
      id: 'p-camacho',
      nombre: 'Elsa Camacho Ruiz',
      carneIdentidad: '82070455602',
      edad: 44,
      sexo: Sexo.femenino,
      hc: '41-2231',
      telefono: '5 337 9028',
      direccion: 'Calle 12 nº 305, Rpto. Chicharrones, mun. Santiago',
      protocolo: Protocolo.nuevo,
      recolectorId: 'u-perez',
      diasDesdeEnrolamiento: 2,
      estados: [
        VisitStatus.enviada,
        VisitStatus.enCaptura,
        VisitStatus.programada,
        VisitStatus.programada,
        VisitStatus.programada,
      ],
      sync: SyncStatus.enCola,
    ),
  ];

  /// Valores clínicos por posición de visita. La tercera reproduce la maqueta,
  /// temperatura fuera de rango incluida.
  static Map<String, Object?> valores(int indiceDia) => switch (indiceDia) {
        2 => const {
            'ta': '148/92',
            'fc': 88,
            'fr': 20,
            'temp': 38.7,
            'spo2': 94,
            'sintomas': ['Fiebre', 'Disnea'],
            'observaciones':
                'Persiste febrícula vespertina. Tolera la vía oral. Se mantiene '
                    'esquema según rama asignada; sin eventos adversos referidos.',
          },
        0 => const {
            'ta': '136/84',
            'fc': 82,
            'fr': 18,
            'temp': 37.2,
            'spo2': 96,
            'peso': 71.5,
            'sintomas': ['Fiebre', 'Tos'],
            'observaciones':
                'Ingresa por cuadro febril de 48 h. Inicia esquema asignado.',
          },
        _ => const {
            'ta': '132/80',
            'fc': 76,
            'fr': 17,
            'temp': 36.9,
            'spo2': 97,
            'sintomas': ['Astenia'],
            'observaciones': 'Evolución favorable. Continúa esquema.',
          },
      };

  /// Historial de auditoría de muestra. `entidadId` apunta a la visita por
  /// `paciente/día`, y cada almacén lo resuelve a su identificador real.
  static final auditoria = <DemoAuditoria>[
    DemoAuditoria(
      ocurridoEn: DateTime(2026, 8, 20, 8, 12),
      autor: Seed.guerra,
      pacienteId: 'p-estevez',
      dia: 3,
      campo: 'temp',
      valorAnterior: '39.7',
      valorNuevo: '38.7',
      motivo: 'error de tecleo',
    ),
    DemoAuditoria(
      ocurridoEn: DateTime(2026, 8, 19, 16, 40),
      autor: Seed.guerra,
      pacienteId: 'p-napoles',
      dia: 5,
      campo: 'estado',
      valorAnterior: 'programada',
      valorNuevo: 'perdida',
      motivo: 'paciente no localizado en dos intentos',
    ),
    DemoAuditoria(
      ocurridoEn: DateTime(2026, 8, 19, 11, 5),
      autor: Seed.morales,
      pacienteId: 'p-saez',
      dia: null,
      campo: 'telefono',
      valorAnterior: '5 663 5509',
      valorNuevo: '5 663 5510',
      motivo: 'solicitado por el recolector',
    ),
    DemoAuditoria(
      ocurridoEn: DateTime(2026, 8, 18, 9, 22),
      autor: Seed.guerra,
      pacienteId: 'p-saez',
      dia: 10,
      campo: 'spo2',
      valorAnterior: '9.4',
      valorNuevo: '94',
      motivo: 'punto decimal mal introducido',
    ),
  ];

  /// Nombre del paciente de demostración, para componer la referencia corta
  /// del historial de auditoría.
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
    required this.direccion,
    required this.protocolo,
    required this.recolectorId,
    required this.diasDesdeEnrolamiento,
    required this.estados,
    required this.sync,
  });

  final String id;
  final String nombre;
  final String carneIdentidad;
  final int edad;
  final Sexo sexo;
  final String hc;
  final String telefono;
  final String direccion;
  final Protocolo protocolo;
  final String recolectorId;

  /// Cuántos días antes de [Seed.hoy] se enroló.
  final int diasDesdeEnrolamiento;

  /// Estado de cada visita, en el orden de `diasVisita`.
  final List<VisitStatus> estados;
  final SyncStatus sync;

  DateTime get enroladoEn =>
      Seed.hoy.subtract(Duration(days: diasDesdeEnrolamiento));

  String get apellidos {
    final partes = nombre.split(' ');
    return partes.length <= 2 ? nombre : partes.sublist(1).join(' ');
  }
}

class DemoAuditoria {
  const DemoAuditoria({
    required this.ocurridoEn,
    required this.autor,
    required this.pacienteId,
    required this.dia,
    required this.campo,
    required this.valorAnterior,
    required this.valorNuevo,
    required this.motivo,
  });

  final DateTime ocurridoEn;
  final Investigador autor;
  final String pacienteId;

  /// `null` si la corrección fue sobre la ficha y no sobre una visita.
  final int? dia;
  final String campo;
  final String? valorAnterior;
  final String? valorNuevo;
  final String motivo;

  AuditEntity get entidad => dia == null ? AuditEntity.ficha : AuditEntity.visita;

  String get descripcionObjetivo =>
      '${Demo.porId(pacienteId).apellidos} · ${dia == null ? 'ficha' : 'D$dia'}';
}
