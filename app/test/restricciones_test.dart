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

  group('§4 · asignación aleatoria por computadora, desacoplada', () {
    test('la secuencia se genera desde una semilla y se consume en orden', () {
      final secuencia = AllocationSequence.generada(
          semilla: 12345, longitud: 8, ahora: DateTime(2026));
      final estrategia = SequentialAllocation(secuencia: secuencia);

      for (var i = 0; i < secuencia.longitud; i++) {
        expect(estrategia.asignar(ahora: DateTime(2026)).protocolo,
            secuencia.valores[i]);
      }
      expect(estrategia.restantes, 0);
    });

    test('la misma semilla reproduce exactamente la misma secuencia', () {
      // Esta es la propiedad que hace auditable la aleatorización: un tercero
      // regenera la secuencia con la semilla del acta y comprueba que las
      // asignaciones registradas son las que tocaban.
      final a = AllocationSequence.generada(
          semilla: 987, longitud: 64, ahora: DateTime(2026));
      final b = AllocationSequence.generada(
          semilla: 987, longitud: 64, ahora: DateTime(2027));

      expect(a.codigoBinario, b.codigoBinario);
      expect(a.verificaContraSemilla(), isTrue);
    });

    test('el generador reproduce sus vectores de verificación', () {
      // Si esto falla, el algoritmo de sorteo cambió: toda secuencia generada
      // antes deja de poder regenerarse, y con ella la auditoría de las
      // asignaciones ya hechas. No se ajusta el vector — se investiga por qué
      // cambió el generador.
      expect(
        AllocationSequence.generada(
                semilla: 12345, longitud: 16, ahora: DateTime(2026))
            .codigoBinario,
        '1101101100000100',
      );
      expect(
        AllocationSequence.generada(
                semilla: 987, longitud: 32, ahora: DateTime(2026))
            .codigoBinario,
        '10111100101110101111001101000111',
      );
    });

    test('semillas distintas dan secuencias distintas', () {
      final a = AllocationSequence.generada(
          semilla: 1, longitud: 64, ahora: DateTime(2026));
      final b = AllocationSequence.generada(
          semilla: 2, longitud: 64, ahora: DateTime(2026));

      expect(a.codigoBinario, isNot(b.codigoBinario));
    });

    test('el código binario tiene una cifra por asignación', () {
      final s = AllocationSequence.generada(
          semilla: 42, longitud: 30, ahora: DateTime(2026));

      expect(s.codigoBinario.length, 30);
      expect(RegExp(r'^[01]+$').hasMatch(s.codigoBinario), isTrue);
      expect(s.reparto.vigente + s.reparto.nuevo, 30);
    });

    test('la secuencia reparte las dos ramas sin fijar proporción exacta', () {
      // Aleatorización simple: se espera un reparto cercano a la mitad, pero
      // NO exactamente la mitad. Si alguien "arregla" esto para que salga
      // 50/50 clavado, ha dejado de ser aleatorización simple.
      final s = AllocationSequence.generada(
          semilla: 20260814, longitud: 200, ahora: DateTime(2026));

      expect(s.reparto.vigente, 106);
      expect(s.reparto.nuevo, 94);
    });

    test('una secuencia cargada desde fuera no lleva semilla ni se autoverifica',
        () {
      final s = AllocationSequence.cargada(
          valores: const [Protocolo.nuevo, Protocolo.vigente],
          etiqueta: 'lista del bioestadista',
          ahora: DateTime(2026));

      expect(s.semilla, isNull);
      expect(s.verificaContraSemilla(), isFalse);
      expect(s.codigoBinario, '10');
    });

    test('agotar la secuencia es un error, no una improvisación', () {
      final estrategia = SequentialAllocation(
        secuencia: AllocationSequence.generada(
            semilla: 7, longitud: 1, ahora: DateTime(2026)),
      );
      estrategia.asignar(ahora: DateTime(2026));

      expect(() => estrategia.asignar(ahora: DateTime(2026)),
          throwsA(isA<AllocationExhausted>()));
    });

    test('cada asignación queda trazada con secuencia, posición y hora', () {
      final p = enrolarDemo();
      expect(p.bloqueAleatorizacion, Seed.secuenciaAleatorizacion.etiqueta);
      expect(p.asignadoEn, isNotNull);
    });

    test('la asignación del estudio coincide con la secuencia sembrada', () {
      // El octavo paciente enrolado recibe la octava entrada: los siete
      // primeros son los de demostración.
      final p = enrolarDemo();
      expect(Seed.secuenciaAleatorizacion.codigoBinario.substring(0, 12),
          '110111110001');
      expect(p.protocolo, Seed.secuenciaAleatorizacion.valores[7]);
      expect(p.protocolo, Protocolo.nuevo);
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
