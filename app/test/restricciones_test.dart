import 'package:flutter_test/flutter_test.dart';
import 'package:sivap/data/allocation/allocation_strategy.dart';
import 'package:sivap/data/local/in_memory_study_repository.dart';
import 'package:sivap/data/local/seed_data.dart';
import 'package:sivap/domain/models/estudio_form_definition.dart';
import 'package:sivap/domain/models/evento_clinico.dart';
import 'package:sivap/domain/models/institucion.dart';
import 'package:sivap/domain/models/patient.dart';
import 'package:sivap/domain/models/protocolo.dart';
import 'package:sivap/domain/models/role.dart';
import 'package:sivap/domain/repositories/study_repository.dart';

/// Las restricciones no negociables de CLAUDE.md, como pruebas.
///
/// Si alguna de estas falla, no es un test roto: es el ensayo dejando de ser
/// válido. Nadie debe "arreglarlas" relajando la aserción.
void main() {
  late InMemoryStudyRepository repo;

  setUp(() => repo = InMemoryStudyRepository());

  Patient enrolarDemo({Institucion? institucion}) => repo.enrolar(
        autor: Seed.reclutador,
        institucion: institucion ?? Seed.coordinador,
        nombre: 'Paciente de Prueba',
        numeroHistoriaClinica: 'TEST-01',
        telefonoPrincipal: '5 000 0000',
        edad: 36,
        sexo: Sexo.femenino,
      );

  Patient conConsentimiento() {
    final p = enrolarDemo();
    repo.registrarConsentimiento(
        autor: Seed.reclutador, patientId: p.id, firmaTrazos: const []);
    return p;
  }

  /// Registra con la función que corresponde a ese hito: el aplicador captura
  /// las fases del protocolo, el evaluador los desenlaces.
  EventoClinico registrar(
    Patient p,
    TipoEvento tipo,
    Map<String, Object?> valores,
  ) {
    final autor = Seed.investigadores.firstWhere((i) => i.puedeCapturar(tipo));
    return repo.registrarEvento(
      autor: autor,
      patientId: p.id,
      tipo: tipo,
      fechaOcurrencia: DateTime(2026, 8, 20),
      valores: valores,
    );
  }

  group('§1 · separación ficha / datos clínicos', () {
    test('el evento no guarda identidad, solo el vínculo interno', () {
      final p = conConsentimiento();
      final e = registrar(p, TipoEvento.enrolamiento, const {'fio2': 40});

      expect(e.patientId, p.id);
      // El dataset clínico debe poder exportarse sin identidad.
      expect(e.valores.values.whereType<String>(),
          everyElement(isNot(contains(p.nombre))));
      expect(e.valores.containsKey('nombre'), isFalse);
      expect(e.valores.containsKey('carneIdentidad'), isFalse);
    });
  });

  group('§3 · sin ediciones silenciosas', () {
    test('un evento registrado no se sobrescribe por la vía normal', () {
      final p = conConsentimiento();
      final e = registrar(p, TipoEvento.extubacion, const {'duracion_total_vmi': 4});

      // Al no ser repetible y estar ya registrado, el sistema se niega a crear
      // otro en su lugar: hay que corregir, no duplicar.
      expect(
        () => repo.guardarBorrador(
          autor: Seed.reclutador,
          patientId: p.id,
          tipo: TipoEvento.extubacion,
          fechaOcurrencia: DateTime(2026, 8, 20),
          valores: const {'duracion_total_vmi': 9},
        ),
        throwsA(isA<EventoNoRepetible>()),
      );
      expect(repo.evento(e.id)!.valores['duracion_total_vmi'], 4);
    });

    test('corregir sin motivo se rechaza', () {
      final p = conConsentimiento();
      final e = registrar(p, TipoEvento.extubacion, const {'duracion_total_vmi': 4});

      expect(
        () => repo.corregirEventoRegistrado(
            autor: Seed.principal,
            eventoId: e.id,
            campo: 'duracion_total_vmi',
            valorNuevo: 6,
            motivo: '   '),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('corregir deja valor anterior, valor nuevo, autor y motivo', () {
      final p = conConsentimiento();
      final e = registrar(p, TipoEvento.extubacion, const {'duracion_total_vmi': 40});

      final antes = repo.auditoria().length;
      repo.corregirEventoRegistrado(
        autor: Seed.principal,
        eventoId: e.id,
        campo: 'duracion_total_vmi',
        valorNuevo: 4,
        motivo: 'cero de más',
      );

      final entrada = repo.auditoria().first;
      expect(repo.auditoria().length, antes + 1);
      expect(entrada.campo, 'duracion_total_vmi');
      expect(entrada.valorAnterior, '40');
      expect(entrada.valorNuevo, '4');
      expect(entrada.autorId, Seed.principal.id);
      expect(entrada.motivo, 'cero de más');
      expect(repo.evento(e.id)!.valores['duracion_total_vmi'], 4);
    });

    test('la corrección devuelve el registro a la cola de envío', () {
      final p = conConsentimiento();
      final e = registrar(p, TipoEvento.extubacion, const {'duracion_total_vmi': 4});
      repo.corregirEventoRegistrado(
          autor: Seed.principal,
          eventoId: e.id,
          campo: 'duracion_total_vmi',
          valorNuevo: 6,
          motivo: 'relectura de la historia');

      expect(repo.evento(e.id)!.sync, SyncStatus.enCola);
    });
  });

  group('§4 · captura por eventos, no por calendario', () {
    test('enrolar no crea ningún registro: los eventos aparecen al ocurrir', () {
      final p = enrolarDemo();

      expect(repo.eventosDe(p.id), isEmpty);
    });

    test('un hito repetible admite varias ocurrencias, numeradas', () {
      final p = conConsentimiento();

      final uno = registrar(p, TipoEvento.cribado, const {'cumple_criterios': false});
      final dos = registrar(p, TipoEvento.cribado, const {'cumple_criterios': false});
      final tres = registrar(p, TipoEvento.cribado, const {'cumple_criterios': true});

      expect([uno.ocurrencia, dos.ocurrencia, tres.ocurrencia], [1, 2, 3]);
      expect(repo.eventosDe(p.id).where((e) => e.tipo == TipoEvento.cribado).length, 3);
    });

    test('un hito no repetible no se duplica: se corrige', () {
      final p = conConsentimiento();
      registrar(p, TipoEvento.egresoUci, const {'estancia_uci': 10});

      expect(
        () => registrar(p, TipoEvento.egresoUci, const {'estancia_uci': 11}),
        throwsA(isA<EventoNoRepetible>()),
      );
    });

    test('la PVE, que es el caso que el modelo anterior no podía representar',
        () {
      final p = conConsentimiento();
      for (var i = 0; i < 4; i++) {
        registrar(p, TipoEvento.pruebaVentilacionEspontanea,
            {'metodo_pve': 'Tubo en T', 'rsbi_inicio': 90 + i});
      }

      final intentos = repo
          .eventosDe(p.id)
          .where((e) => e.tipo == TipoEvento.pruebaVentilacionEspontanea)
          .toList();
      expect(intentos.length, 4);
      expect(intentos.map((e) => e.ocurrencia), [1, 2, 3, 4]);
    });

    test('una trayectoria incompleta no es un error', () {
      // Traqueostomía: el paciente sale del proceso y nunca llega a extubarse.
      // No hay nada que marcar como perdido — esos eventos simplemente no
      // existen.
      final p = conConsentimiento();
      registrar(p, TipoEvento.cribado, const {'cumple_criterios': false});
      registrar(p, TipoEvento.traqueostomia,
          const {'fecha_traqueostomia': '2026-08-18'});

      final tipos = repo.eventosDe(p.id).map((e) => e.tipo).toSet();
      expect(tipos, contains(TipoEvento.traqueostomia));
      expect(tipos, isNot(contains(TipoEvento.extubacion)));
    });

    test('no existe un estado de evento «perdido»', () {
      expect(EstadoEvento.values.map((e) => e.name),
          isNot(contains(anyOf('perdida', 'perdido'))));
    });

    test('la fecha del evento es la real, no una programada', () {
      final p = conConsentimiento();
      final ocurrio = DateTime(2026, 8, 11);
      final e = repo.registrarEvento(
        autor: Seed.reclutador,
        patientId: p.id,
        tipo: TipoEvento.traqueostomia,
        fechaOcurrencia: ocurrio,
        valores: const {'fecha_traqueostomia': '2026-08-11'},
      );

      expect(e.fechaOcurrencia, ocurrio);
      // Y la fecha de captura es otra cosa: cuándo se tecleó.
      expect(e.fechaCaptura, isNotNull);
    });
  });

  group('§5 · formularios configurables', () {
    test('los hitos con formulario salen de la definición, no del código', () {
      const def = Seed.formulario;

      expect(def.tieneFormulario(TipoEvento.pruebaVentilacionEspontanea), isTrue);
      expect(def.para(TipoEvento.cribado)!.campos, isNotEmpty);
    });

    test('cada definición pertenece a su tipo de evento', () {
      for (final e in Seed.formulario.eventos) {
        expect(e.tipo, isA<TipoEvento>());
        expect(e.secciones, isNotEmpty, reason: e.tipo.name);
      }
    });

    test('el rango clínico avisa pero no impide registrar el valor real', () {
      const campo = FieldDefinition(
          key: 'fr', label: 'FR', tipo: FieldType.numero, min: 5, max: 60);

      expect(campo.fueraDeRango(22), isNull);
      expect(campo.fueraDeRango(70), isNotNull);
      expect(campo.fueraDeRango(null), isNull);
    });

    test('los campos del Anexo 4 no traen rangos sin validar', () {
      // Los rangos anteriores eran de paciente general ambulatorio y un
      // paciente ventilado en UCI los excede con normalidad. Van vacíos hasta
      // que un intensivista los fije: un aviso falso repetido enseña al equipo
      // a ignorar los avisos, y entonces tampoco ve los verdaderos.
      for (final e in Seed.formulario.eventos) {
        for (final c in e.campos) {
          expect(c.min, isNull, reason: '${e.tipo.name}.${c.key}');
          expect(c.max, isNull, reason: '${e.tipo.name}.${c.key}');
        }
      }
    });

    test('los cuatro módulos del Anexo 4 están representados', () {
      final claves = {
        for (final e in Seed.formulario.eventos)
          for (final c in e.campos) c.key
      };

      // Módulo 1
      expect(claves, containsAll(['fecha_ingreso_uci', 'causa_intubacion',
          'comorbilidades', 'imc']));
      // Módulo 2
      expect(claves, containsAll(['fecha_inicio_vmi', 'fio2', 'peep',
          'metodo_pve', 'rsbi_inicio', 'rsbi_final', 'resultado_pve']));
      // Módulo 3
      expect(claves, containsAll(['test_fuga', 'resultado_test_fuga',
          'duracion_total_vmi']));
      // Módulo 4
      expect(claves, containsAll(['reintubacion_72h', 'causa_reintubacion',
          'eventos_adversos', 'estancia_uci', 'estado_egreso',
          'fallecimiento_post_egreso']));
    });

    test('el RSBI usa las categorías del Anexo 4', () {
      final rsbi = Seed.formulario
          .para(TipoEvento.pruebaVentilacionEspontanea)!
          .campos
          .firstWhere((c) => c.key == 'rsbi_inicio');

      expect(rsbi.opciones, ['> 105', '≤ 105', '≤ 58']);
    });

    test('«total de PVE intentadas» no se pide: se cuenta', () {
      // Pedir dos veces el mismo dato es pedir que discrepen. El propio Anexo
      // señala que es derivable.
      final claves = {
        for (final e in Seed.formulario.eventos)
          for (final c in e.campos) c.key
      };
      expect(claves, isNot(contains('total_pve_intentadas')));
    });
  });

  group('§6 · asignación aleatoria por computadora, desacoplada', () {
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
      // asignaciones ya hechas.
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

    test('el código binario tiene una cifra por asignación', () {
      final s = AllocationSequence.generada(
          semilla: 42, longitud: 30, ahora: DateTime(2026));

      expect(s.codigoBinario.length, 30);
      expect(s.reparto.a + s.reparto.b, 30);
    });

    test('la secuencia reparte las dos ramas sin fijar proporción exacta', () {
      // Aleatorización simple: reparto cercano a la mitad, pero NO la mitad
      // exacta. Si alguien lo "arregla" para que salga 50/50 clavado, ha
      // dejado de ser aleatorización simple.
      final s = AllocationSequence.generada(
          semilla: 20260814, longitud: 200, ahora: DateTime(2026));

      expect(s.reparto.a, 106);
      expect(s.reparto.b, 94);
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

    test('no hay forma de consultar la rama siguiente sin consumirla', () {
      // Saber qué rama toca antes de decidir a quién se enrola es el sesgo de
      // selección que la aleatorización existe para evitar. La API no lo
      // permite, y es deliberado (CLAUDE.md §6).
      final estrategia = SequentialAllocation(
        secuencia: AllocationSequence.generada(
            semilla: 7, longitud: 4, ahora: DateTime(2026)),
      );

      expect(estrategia.restantes, 4);
      // `asignar` es la única salida, y consume.
      estrategia.asignar(ahora: DateTime(2026));
      expect(estrategia.restantes, 3);
    });

    test('cada asignación queda trazada con secuencia y hora', () {
      final p = enrolarDemo();

      expect(p.secuencia, Seed.secuenciaAleatorizacion.etiqueta);
      expect(p.posicionSecuencia, greaterThan(0));
      expect(p.protocolo, isIn(Protocolo.values));
    });
  });

  group('§11 · roles y permisos', () {
    test('el observador no enrola ni captura', () {
      expect(
        () => repo.enrolar(
            autor: Seed.observador,
            institucion: Seed.coordinador,
            nombre: 'X',
            numeroHistoriaClinica: '1',
            telefonoPrincipal: '1',
            edad: 1,
            sexo: Sexo.masculino),
        throwsA(isA<PermissionDenied>()),
      );
    });

    test('el recolector no corrige registros ya enviados', () {
      final p = conConsentimiento();
      final e = registrar(p, TipoEvento.extubacion, const {'duracion_total_vmi': 4});

      expect(
        () => repo.corregirEventoRegistrado(
            autor: Seed.reclutador,
            eventoId: e.id,
            campo: 'duracion_total_vmi',
            valorNuevo: 6,
            motivo: 'me equivoqué'),
        throwsA(isA<PermissionDenied>()),
      );
    });

    test('el recolector solo ve su propia carga', () {
      final suyos = repo.pacientes(recolectorId: Seed.reclutador.id);

      expect(suyos, isNotEmpty);
      expect(suyos.every((p) => p.recolectorId == Seed.reclutador.id), isTrue);
      expect(suyos.length, lessThan(repo.pacientes().length));
    });
  });

  group('§13 · consentimiento informado', () {
    test('sin consentimiento no se capturan eventos', () {
      final p = enrolarDemo();
      expect(p.tieneConsentimiento, isFalse);

      expect(
        () => registrar(p, TipoEvento.cribado, const {'cumple_criterios': true}),
        throwsStateError,
      );
    });

    test('el consentimiento registra la versión del documento', () {
      final p = enrolarDemo();
      final consent = repo.registrarConsentimiento(
          autor: Seed.reclutador, patientId: p.id, firmaTrazos: const []);

      expect(consent.versionDocumento, repo.config.documentoConsentimiento.version);
      expect(repo.paciente(p.id)!.tieneConsentimiento, isTrue);
    });

    test('el estudio arranca sin aprobación del CEI', () {
      // Cambiar esto a `true` es una decisión del equipo, documentada, no un
      // ajuste de código para que la demostración quede más bonita.
      expect(repo.config.consentimientoAprobadoPorCei, isFalse);
    });
  });

  group('§8 · multicéntrico', () {
    test('el paciente declara su centro y el código lo lleva de prefijo', () {
      final p = enrolarDemo(institucion: Seed.cardiologia);

      expect(p.institucion, Seed.cardiologia);
      expect(p.codigo, startsWith('${Seed.cardiologia.codigo}-'));
    });

    test('el correlativo del código es por centro, no global', () {
      final a = enrolarDemo(institucion: Seed.militar);
      final b = enrolarDemo(institucion: Seed.militar);

      expect(a.codigo, isNot(b.codigo));
      expect(a.codigo, startsWith('HM-'));
      expect(b.codigo, startsWith('HM-'));
    });

    test('el evento guarda dónde se capturó, no solo dónde se enroló', () {
      // Un paciente trasladado tendría eventos de más de un centro, y el
      // análisis por centro necesita saber dónde ocurrió cada cosa.
      final p = conConsentimiento();
      final e = registrar(p, TipoEvento.cribado, const {'cumple_criterios': true});

      expect(e.institucion, isNotNull);
    });
  });

  group('§9 · minimización de datos personales', () {
    test('la ficha no admite carné de identidad ni dirección', () {
      // No hay dónde ponerlos: el Anexo 4 no los pide y cada dato personal de
      // más hay que justificarlo ante el Comité de Ética.
      final p = enrolarDemo();
      final campos = p.toString();

      expect(campos, isNot(contains('carne')));
      expect(p.telefonoSecundario, isNull);
    });
  });

  group('§2 y BASES §4 · separación de funciones', () {
    test('el aplicador no registra desenlaces', () {
      final p = conConsentimiento();

      expect(
        () => repo.registrarEvento(
            autor: Seed.aplicador,
            patientId: p.id,
            tipo: TipoEvento.reintubacion,
            fechaOcurrencia: DateTime(2026, 8, 20),
            valores: const {'reintubacion_72h': false}),
        throwsA(isA<FueraDeSuFuncion>()),
      );
    });

    test('el evaluador no registra fases del protocolo', () {
      final p = conConsentimiento();

      expect(
        () => repo.registrarEvento(
            autor: Seed.evaluador,
            patientId: p.id,
            tipo: TipoEvento.pruebaVentilacionEspontanea,
            fechaOcurrencia: DateTime(2026, 8, 20),
            valores: const {'metodo_pve': 'PSV'}),
        throwsA(isA<FueraDeSuFuncion>()),
      );
    });

    test('el evaluador de desenlaces no ve la rama asignada', () {
      // Si la viera, su juicio sobre si hubo extubación fallida —el desenlace
      // principal— dejaría de ser independiente.
      expect(Seed.evaluador.veRamaAsignada, isFalse);
      expect(Seed.aplicador.veRamaAsignada, isTrue);
      expect(Seed.principal.veRamaAsignada, isTrue);
    });

    test('acumular aplicador y evaluador oculta la rama, no la muestra', () {
      // En cegamiento manda la restricción más estricta, no la suma de
      // permisos.
      const acumula = Investigador(
        id: 'u-x',
        usuario: 'x',
        nombre: 'Dr. X',
        roles: {Rol.aplicador, Rol.evaluadorDesenlaces},
        institucion: Seed.coordinador,
      );

      expect(acumula.veRamaAsignada, isFalse);
      expect(acumula.acumulaFuncionesIncompatibles, isTrue);
    });

    test('solo el investigador principal corrige', () {
      for (final i in Seed.investigadores) {
        expect(i.puedeCorregirRegistrado,
            i.roles.contains(Rol.investigadorPrincipal),
            reason: i.usuario);
      }
    });

    test('el analista exporta pero no captura', () {
      expect(Seed.analista.puedeExportar, isTrue);
      expect(Seed.analista.puedeCapturarEventos, isFalse);
      expect(Seed.analista.puedeEnrolar, isFalse);
    });

    test('cada hito del estudio tiene una función que lo captura', () {
      // Si un hito no lo captura nadie, el dato no se recoge y nadie se entera
      // hasta el análisis.
      for (final tipo in TipoEvento.values) {
        expect(Rol.values.any((r) => r.eventosQueCaptura.contains(tipo)), isTrue,
            reason: tipo.name);
      }
    });
  });
}
