import 'package:flutter_test/flutter_test.dart';
import 'package:sivap/data/allocation/allocation_strategy.dart';
import 'package:sivap/data/local/in_memory_study_repository.dart';
import 'package:sivap/data/local/seed_data.dart';
import 'package:sivap/domain/models/patient.dart';
import 'package:sivap/domain/models/protocolo.dart';
import 'package:sivap/domain/models/visit.dart';
import 'package:sivap/domain/repositories/study_repository.dart';

/// Las restricciones no negociables de CLAUDE.md, como pruebas.
///
/// Si alguna de estas falla, no es un test roto: es el estudio dejando de ser
/// válido. Nadie debe "arreglarlas" relajando la aserción.
void main() {
  late InMemoryStudyRepository repo;

  setUp(() => repo = InMemoryStudyRepository());

  Patient enrolarDemo({String nombre = 'Paciente de Prueba'}) => repo.enrolar(
        autor: Seed.morales,
        nombre: nombre,
        carneIdentidad: '90010112345',
        edad: 36,
        sexo: Sexo.femenino,
        numeroHistoriaClinica: '41-9999',
        telefono: '5 000 0000',
        direccion: 'Sin dirección',
      );

  group('§1 · separación ficha / visita', () {
    test('la visita no guarda identidad, solo el vínculo interno', () {
      final p = enrolarDemo();
      final visitas = repo.visitasDe(p.id);

      expect(visitas, isNotEmpty);
      for (final v in visitas) {
        expect(v.patientId, p.id);
        // El dataset clínico debe poder exportarse sin identidad: ningún valor
        // capturado puede contener el nombre ni el carné del paciente.
        expect(v.valores.values.whereType<String>(),
            everyElement(isNot(contains(p.nombre))));
        expect(v.valores.containsKey('nombre'), isFalse);
        expect(v.valores.containsKey('carneIdentidad'), isFalse);
      }
    });
  });

  group('§2 · sin ediciones silenciosas', () {
    test('una visita cerrada no se puede sobrescribir por la vía normal', () {
      final p = enrolarDemo();
      repo.registrarConsentimiento(
          autor: Seed.morales, patientId: p.id, firmaTrazos: const []);
      repo.cerrarVisita(
          autor: Seed.morales, patientId: p.id, dia: 1, valores: const {'fc': 80});

      expect(
        () => repo.guardarBorrador(
            autor: Seed.morales, patientId: p.id, dia: 1, valores: const {'fc': 99}),
        throwsA(isA<SilentEditRejected>()),
      );
      expect(repo.visita(p.id, 1)!.valores['fc'], 80);
    });

    test('corregir sin motivo se rechaza', () {
      final p = enrolarDemo();
      repo.registrarConsentimiento(
          autor: Seed.morales, patientId: p.id, firmaTrazos: const []);
      repo.cerrarVisita(
          autor: Seed.morales, patientId: p.id, dia: 1, valores: const {'fc': 80});

      expect(
        () => repo.corregirVisitaEnviada(
            autor: Seed.guerra,
            patientId: p.id,
            dia: 1,
            campo: 'fc',
            valorNuevo: 88,
            motivo: '   '),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('corregir deja valor anterior, valor nuevo, autor y motivo', () {
      final p = enrolarDemo();
      repo.registrarConsentimiento(
          autor: Seed.morales, patientId: p.id, firmaTrazos: const []);
      repo.cerrarVisita(
          autor: Seed.morales, patientId: p.id, dia: 1, valores: const {'temp': 39.7});

      final antes = repo.auditoria().length;
      repo.corregirVisitaEnviada(
        autor: Seed.guerra,
        patientId: p.id,
        dia: 1,
        campo: 'temp',
        valorNuevo: 38.7,
        motivo: 'error de tecleo',
      );

      final entrada = repo.auditoria().first;
      expect(repo.auditoria().length, antes + 1);
      expect(entrada.campo, 'temp');
      expect(entrada.valorAnterior, '39.7');
      expect(entrada.valorNuevo, '38.7');
      expect(entrada.autorId, Seed.guerra.id);
      expect(entrada.motivo, 'error de tecleo');
      expect(repo.visita(p.id, 1)!.valores['temp'], 38.7);
    });

    test('la corrección devuelve el registro a la cola de envío', () {
      final p = enrolarDemo();
      repo.registrarConsentimiento(
          autor: Seed.morales, patientId: p.id, firmaTrazos: const []);
      repo.cerrarVisita(
          autor: Seed.morales, patientId: p.id, dia: 1, valores: const {'fc': 80});
      repo.corregirVisitaEnviada(
          autor: Seed.guerra,
          patientId: p.id,
          dia: 1,
          campo: 'fc',
          valorNuevo: 88,
          motivo: 'relectura del parte');

      expect(repo.visita(p.id, 1)!.sync, SyncStatus.enCola);
    });
  });

  group('§3 · formularios configurables', () {
    test('los días de visita salen de la definición, no del código', () {
      final p = enrolarDemo();
      expect(repo.visitasDe(p.id).map((v) => v.dia).toList(),
          repo.config.definicionFormulario.diasVisita);
    });

    test('un campo restringido a ciertos días solo aparece en esos días', () {
      final def = Seed.formulario;
      final temp = def.camposPara(1).firstWhere((c) => c.key == 'temp');

      expect(temp.aplicaA(1), isTrue);
      expect(temp.aplicaA(14), isTrue, reason: 'sin `dias`, aplica a todos');
      expect(def.seccionesPara(3).map((s) => s.titulo),
          contains('Signos vitales'));
    });

    test('el rango clínico avisa pero no impide registrar el valor real', () {
      final temp = Seed.formulario.camposPara(5).firstWhere((c) => c.key == 'temp');

      expect(temp.fueraDeRango(36.8), isNull);
      expect(temp.fueraDeRango(38.7), isNotNull);
      expect(temp.fueraDeRango(null), isNull);
    });
  });

  group('§4 · asignación desacoplada', () {
    test('la secuencia pre-generada se consume en orden', () {
      final estrategia = PreGeneratedSequenceAllocation(
        secuencia: const [Protocolo.nuevo, Protocolo.vigente, Protocolo.nuevo],
        etiquetaBloque: 'bloque de prueba',
      );

      expect(estrategia.asignar(ahora: DateTime(2026)).protocolo, Protocolo.nuevo);
      expect(estrategia.asignar(ahora: DateTime(2026)).protocolo, Protocolo.vigente);
      expect(estrategia.asignar(ahora: DateTime(2026)).protocolo, Protocolo.nuevo);
      expect(estrategia.restantes, 0);
    });

    test('agotar la secuencia es un error, no una improvisación', () {
      final estrategia = PreGeneratedSequenceAllocation(
          secuencia: const [Protocolo.nuevo], etiquetaBloque: 'b');
      estrategia.asignar(ahora: DateTime(2026));

      expect(() => estrategia.asignar(ahora: DateTime(2026)),
          throwsA(isA<AllocationExhausted>()));
    });

    test('la asignación queda trazada con bloque y hora', () {
      final p = enrolarDemo();
      expect(p.bloqueAleatorizacion, isNotEmpty);
      expect(p.asignadoEn, isNotNull);
    });
  });

  group('§6 · roles y permisos', () {
    test('el observador no enrola ni captura', () {
      expect(
        () => repo.enrolar(
            autor: Seed.betancourt,
            nombre: 'X',
            carneIdentidad: '1',
            edad: 1,
            sexo: Sexo.masculino,
            numeroHistoriaClinica: '1',
            telefono: '1',
            direccion: '1'),
        throwsA(isA<PermissionDenied>()),
      );
    });

    test('el recolector no corrige registros ya enviados', () {
      final p = enrolarDemo();
      repo.registrarConsentimiento(
          autor: Seed.morales, patientId: p.id, firmaTrazos: const []);
      repo.cerrarVisita(
          autor: Seed.morales, patientId: p.id, dia: 1, valores: const {'fc': 80});

      expect(
        () => repo.corregirVisitaEnviada(
            autor: Seed.morales,
            patientId: p.id,
            dia: 1,
            campo: 'fc',
            valorNuevo: 88,
            motivo: 'me equivoqué'),
        throwsA(isA<PermissionDenied>()),
      );
    });

    test('el recolector solo ve su propia carga', () {
      final suyos = repo.pacientes(recolectorId: Seed.morales.id);
      expect(suyos, isNotEmpty);
      expect(suyos.every((p) => p.recolectorId == Seed.morales.id), isTrue);
      expect(suyos.length, lessThan(repo.pacientes().length));
    });
  });

  group('§8 · consentimiento informado', () {
    test('sin consentimiento no se capturan visitas', () {
      final p = enrolarDemo();
      expect(p.tieneConsentimiento, isFalse);

      expect(
        () => repo.guardarBorrador(
            autor: Seed.morales, patientId: p.id, dia: 1, valores: const {'fc': 80}),
        throwsStateError,
      );
    });

    test('el consentimiento registra la versión del documento aprobado', () {
      final p = enrolarDemo();
      final consent = repo.registrarConsentimiento(
          autor: Seed.morales, patientId: p.id, firmaTrazos: const []);

      expect(consent.versionDocumento, repo.config.documentoConsentimiento.version);
      expect(consent.codigoCei, repo.config.documentoConsentimiento.codigoCei);
      expect(repo.paciente(p.id)!.tieneConsentimiento, isTrue);
    });

    test('el estudio arranca sin aprobación del CEI', () {
      // Cambiar esto a `true` es una decisión del equipo, documentada, no un
      // ajuste de código para que la demo quede más bonita.
      expect(repo.config.consentimientoAprobadoPorCei, isFalse);
    });
  });
}
