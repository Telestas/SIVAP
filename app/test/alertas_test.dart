import 'package:flutter_test/flutter_test.dart';
import 'package:sivap/data/local/in_memory_study_repository.dart';
import 'package:sivap/data/local/seed_data.dart';
import 'package:sivap/domain/alertas.dart';
import 'package:sivap/domain/models/evento_clinico.dart';
import 'package:sivap/domain/models/patient.dart';

/// Las dos alertas que pide el Anexo 4.
///
/// Lo que se comprueba aquí, más que si aparecen, es **cuándo dejan de
/// aparecer**. Una alerta que no se apaga sola acaba ignorándose, y una lista
/// de avisos que nadie mira es peor que no tenerla.
void main() {
  late InMemoryStudyRepository repo;
  final hoy = DateTime(2026, 10, 1);

  setUp(() => repo = InMemoryStudyRepository());

  Patient enrolarYConsentir() {
    final p = repo.enrolar(
      autor: Seed.reclutador,
      institucion: Seed.coordinador,
      nombre: 'Nombre Inventado',
      numeroHistoriaClinica: 'HC-9',
      telefonoPrincipal: '55512345',
      edad: 62,
      sexo: Sexo.masculino,
    );
    repo.registrarConsentimiento(
        autor: Seed.reclutador, patientId: p.id, firmaTrazos: const []);
    return p;
  }

  void registrar(
    Patient p,
    TipoEvento tipo,
    Map<String, Object?> valores, {
    DateTime? cuando,
  }) =>
      repo.registrarEvento(
        autor: Seed.principal,
        patientId: p.id,
        tipo: tipo,
        fechaOcurrencia: cuando ?? DateTime(2026, 9, 1),
        valores: valores,
      );

  /// Extubado y con desenlaces registrados: vivo y egresado en esa fecha.
  Patient egresadoVivo(DateTime egreso) {
    final p = enrolarYConsentir();
    registrar(p, TipoEvento.extubacion, const {'traqueostomia': false});
    registrar(p, TipoEvento.desenlaces, {
      'reintubacion_72h': false,
      'estado_egreso': 'Vivo',
      'fecha_egreso_uci': '${egreso.year}-'
          '${egreso.month.toString().padLeft(2, '0')}-'
          '${egreso.day.toString().padLeft(2, '0')}',
    });
    return p;
  }

  /// Las alertas de un paciente concreto.
  ///
  /// Acotado a propósito: la app arranca con siete pacientes de demostración
  /// y sus trayectorias también generan avisos. Aquí interesa el caso que cada
  /// prueba monta, no el ruido de fondo.
  List<Alerta> alertas(Patient p, {DateTime? cuando}) =>
      Alertas.pendientes(repo, hoy: cuando ?? hoy)
          .where((a) => a.paciente.id == p.id)
          .toList();

  group('paciente listo para evaluar desenlaces', () {
    test('un paciente extubado sin desenlaces genera el aviso', () {
      final p = enrolarYConsentir();
      registrar(p, TipoEvento.extubacion, const {'traqueostomia': false},
          cuando: DateTime(2026, 9, 28));

      final aviso = alertas(p).single;
      expect(aviso.tipo, TipoAlerta.listoParaEvaluar);
      expect(aviso.paciente.id, p.id);
      expect(aviso.eventoQueLaCierra, TipoEvento.desenlaces);
      expect(aviso.diasEsperando(hoy), 3);
    });

    test('registrar los desenlaces lo apaga, sin cancelar nada', () {
      final p = enrolarYConsentir();
      registrar(p, TipoEvento.extubacion, const {'traqueostomia': false});
      expect(alertas(p).where((a) => a.tipo == TipoAlerta.listoParaEvaluar),
          hasLength(1));

      registrar(p, TipoEvento.desenlaces, const {
        'reintubacion_72h': false,
        'estado_egreso': 'Fallecido',
      });

      expect(alertas(p).where((a) => a.tipo == TipoAlerta.listoParaEvaluar),
          isEmpty);
    });

    test('un paciente traqueostomizado no se extubó, y no genera aviso', () {
      // Su trayectoria se desvió: no hay desenlace de extubación que evaluar.
      final p = enrolarYConsentir();
      registrar(p, TipoEvento.extubacion, const {
        'traqueostomia': true,
        'fecha_traqueostomia': '2026-09-01',
      });

      expect(alertas(p), isEmpty);
    });

    test('un borrador de extubación no cuenta como extubado', () {
      final p = enrolarYConsentir();
      repo.guardarBorrador(
        autor: Seed.principal,
        patientId: p.id,
        tipo: TipoEvento.extubacion,
        fechaOcurrencia: DateTime(2026, 9, 28),
        valores: const {'traqueostomia': false},
      );

      expect(alertas(p), isEmpty);
    });
  });

  group('contactos de seguimiento', () {
    test('a los siete días del egreso toca el primer contacto', () {
      final p = egresadoVivo(DateTime(2026, 9, 24));

      // El día 6 todavía no.
      expect(alertas(p, cuando: DateTime(2026, 9, 30)), isEmpty);
      // El día 7 sí.
      final aviso = alertas(p, cuando: DateTime(2026, 10, 1)).single;
      expect(aviso.tipo, TipoAlerta.contactoSeguimiento);
      expect(aviso.detalle, 'Día 7 tras el egreso');
    });

    test('las tres ventanas se acumulan si no se atienden', () {
      final p = egresadoVivo(DateTime(2026, 9, 1));

      final avisos = alertas(p, cuando: DateTime(2026, 10, 5));

      expect(avisos.map((a) => a.detalle), [
        'Día 7 tras el egreso',
        'Día 14 tras el egreso',
        'Día 28 tras el egreso',
      ]);
      // Lo que lleva más tiempo esperando va primero.
      expect(avisos.first.diasEsperando(DateTime(2026, 10, 5)), 27);
    });

    test('registrar un contacto apaga solo el suyo', () {
      final p = egresadoVivo(DateTime(2026, 9, 1));
      registrar(p, TipoEvento.seguimientoPostEgreso, {
        'ventana_contacto': 'Día 7 tras el egreso',
        'fallecido': false,
      });

      final avisos = alertas(p, cuando: DateTime(2026, 10, 5));

      expect(avisos.map((a) => a.detalle),
          ['Día 14 tras el egreso', 'Día 28 tras el egreso']);
    });

    test('un fallecimiento cierra el seguimiento entero', () {
      // No hace falta cancelar los contactos que quedaban: dejan de proceder.
      final p = egresadoVivo(DateTime(2026, 9, 1));
      registrar(p, TipoEvento.seguimientoPostEgreso, {
        'ventana_contacto': 'Día 7 tras el egreso',
        'fallecido': true,
        'causa_fallecimiento': 'Sepsis',
      });

      expect(alertas(p, cuando: DateTime(2026, 10, 5)), isEmpty);
    });

    test('un paciente que egresó fallecido no genera seguimiento', () {
      final p = enrolarYConsentir();
      registrar(p, TipoEvento.extubacion, const {'traqueostomia': false});
      registrar(p, TipoEvento.desenlaces, const {
        'reintubacion_72h': true,
        'estado_egreso': 'Fallecido',
        'fecha_fallecimiento': '2026-09-10',
      });

      expect(alertas(p, cuando: DateTime(2026, 11, 1)), isEmpty);
    });

    test('sin fecha de egreso no se inventa desde cuándo contar', () {
      final p = enrolarYConsentir();
      registrar(p, TipoEvento.extubacion, const {'traqueostomia': false});
      registrar(p, TipoEvento.desenlaces, const {
        'reintubacion_72h': false,
        'estado_egreso': 'Vivo',
      });

      final avisos = alertas(p, cuando: DateTime(2026, 11, 1));

      // Ni un aviso de seguimiento; el de evaluar tampoco, que ya se registró.
      expect(avisos, isEmpty);
    });
  });

  group('a quién le tocan', () {
    test('el evaluador ve lo que él puede cerrar', () {
      final p = enrolarYConsentir();
      registrar(p, TipoEvento.extubacion, const {'traqueostomia': false});

      final suyas = Alertas.pendientes(repo, hoy: hoy, para: Seed.evaluador)
          .where((a) => a.paciente.id == p.id);

      expect(suyas, hasLength(1));
      expect(suyas.single.tipo, TipoAlerta.listoParaEvaluar);
    });

    test('el reclutador no ve alertas que no puede atender', () {
      // Una lista con avisos que uno no puede resolver se aprende a ignorar.
      final p = enrolarYConsentir();
      registrar(p, TipoEvento.extubacion, const {'traqueostomia': false});

      expect(
        Alertas.pendientes(repo, hoy: hoy, para: Seed.reclutador)
            .where((a) => a.paciente.id == p.id),
        isEmpty,
      );
    });

    test('el investigador principal las ve todas', () {
      final p = egresadoVivo(DateTime(2026, 9, 1));

      expect(
        Alertas.pendientes(repo, hoy: DateTime(2026, 10, 5),
                para: Seed.principal)
            .where((a) => a.paciente.id == p.id),
        hasLength(3),
      );
    });
  });

  test('los datos de demostración no generan una lista imposible de vaciar',
      () {
    // Arrancan con trayectorias completas a propósito. Si generaran avisos que
    // nadie va a atender, la lista nacería inútil.
    final avisos = Alertas.pendientes(repo, hoy: Seed.hoy);

    expect(avisos.where((a) => a.diasEsperando(Seed.hoy) > 60), isEmpty);
  });
}
