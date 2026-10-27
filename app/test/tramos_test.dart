import 'dart:ffi' show DynamicLibrary;

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:sqlite3/open.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:sivap/data/local/db/sivap_database.dart';
import 'package:sivap/data/local/sqlite_study_repository.dart';
import 'package:sivap/data/local/seed_data.dart';
import 'package:sivap/data/exportacion/consentimiento_archivable.dart';
import 'package:sivap/data/remoto/lote.dart';
import 'package:sivap/domain/models/patient.dart';
import 'package:sivap/app.dart';
import 'package:sivap/core/app_state.dart';
import 'package:sivap/core/widgets/controls.dart';
import 'package:sivap/data/local/almacen_local.dart';
import 'package:sivap/features/enrollment/enrollment_screen.dart';
import 'package:sivap/features/consent/consent_screen.dart';

void main() {
  late Database db;
  late SqliteStudyRepository repo;

  setUpAll(() {
    open.overrideFor(
        OperatingSystem.linux, () => DynamicLibrary.open('libsqlite3.so.0'));
  });

  setUp(() {
    db = sqlite3.openInMemory();
    repo = SqliteStudyRepository(SivapDatabase.paraPruebas(db));
    repo.guardarConfiguracionAprobada(
      institucion: Seed.coordinador,
      ceiAprobado: true,
      consentimiento: {
        'aprobado': true,
        'version': 'prueba-1',
        'codigo_cei': 'CEI-PRUEBA',
        'vigente_desde': '2026-10-26',
        'parrafos': ['Texto inventado para pruebas.'],
        'declaraciones': ['Acepto para esta prueba.'],
      },
    );
  });
  tearDown(() => db.dispose());

  Tramo tramo(int desde, String bits) => Tramo(
        desde: desde,
        hasta: desde + bits.length,
        consumidas: 0,
        codigoBinario: bits,
        asignadoEn: DateTime.utc(2026, 10, 26),
      );

  Patient enrolar() => repo.enrolar(
        autor: Seed.reclutador,
        institucion: Seed.coordinador,
        nombre: 'Paciente inventado',
        numeroHistoriaClinica: 'DEMO',
        telefonoPrincipal: '00000000',
        edad: 60,
        sexo: Sexo.femenino,
      );

  test('sin tramo reservado no se enrola ni crea ficha', () {
    expect(() => enrolar(), throwsStateError);
    expect(repo.pacientes(), isEmpty);
  });

  testWidgets('el enrolamiento integrado habilita guardar y firma sobre SQLite',
      (tester) async {
    tester.view.physicalSize = const Size(360, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    repo.guardarConfiguracionAprobada(
        institucion: Seed.coordinador,
        ceiAprobado: false,
        pruebasIntegradas: true,
        consentimiento: {
          'aprobado': false,
          'tipo': 'prueba',
          'habilitado': true,
          'version': 'preproduccion-v1',
          'codigo_cei': 'PRUEBA-SIN-VALIDEZ-CEI',
          'vigente_desde': '2026-10-26',
          'parrafos': ['Documento ficticio para pruebas integradas.'],
          'declaraciones': ['Confirmo que es ficticio.'],
        });
    repo.incorporarTramo(tramo(1, '1'), 'preproduccion-1', 'aparato-1');
    final estado = AppState(AlmacenLocal(
        repo: repo,
        persistente: true,
        cifrado: true,
        descripcion: 'SQLite para prueba integrada'))
      ..iniciarSesion(Seed.principal);
    addTearDown(estado.dispose);
    await tester
        .pumpWidget(raizDeLaApp(estado, inicio: const EnrollmentScreen()));
    await tester.tap(find.text('Ninguno está presente'));
    await tester.pumpAndSettle();
    expect(find.textContaining('PREPRODUCCIÓN'), findsNothing);
    expect(
        tester
            .widget<AppButton>(find.widgetWithText(AppButton, 'Guardar'))
            .enabled,
        isTrue);
    final datos = {
      'Nombre y apellidos': 'Paciente Inventado',
      'Núm. de historia clínica': 'PRUEBA-001',
      'Edad': '60',
      'Teléfono de contacto': '55512345'
    };
    for (final entrada in datos.entries) {
      await tester.enterText(
          find.descendant(
              of: find.byWidgetPredicate(
                  (w) => w is LabeledField && w.label == entrada.key),
              matching: find.byType(TextField)),
          entrada.value);
    }
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();
    expect(repo.pacientes(), hasLength(1));
    expect(repo.asignacionesRestantes, 0);
    await tester.tap(find.text('Ir a consentimiento'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirmo que es ficticio.'));
    await tester.drag(find.byType(SignaturePad), const Offset(100, 20));
    await tester.pump();
    await tester.tap(find.text('Registrar consentimiento'));
    await tester.pumpAndSettle();
    expect(repo.pacientes().single.tieneConsentimiento, isTrue);
    expect(repo.pendienteDeEnvio().consentimientos, hasLength(1));
    expect(tester.takeException(), isNull);
  });

  test('preproducción usa SQLite, tramo y firma sin fingir aprobación clínica',
      () {
    final documento = {
      'aprobado': false,
      'tipo': 'prueba',
      'habilitado': true,
      'version': 'preproduccion-v1',
      'codigo_cei': 'PRUEBA-SIN-VALIDEZ-CEI',
      'vigente_desde': '2026-10-26',
      'parrafos': ['Documento ficticio para pruebas integradas.'],
      'declaraciones': ['Confirmo que es ficticio.'],
    };
    repo.guardarConfiguracionAprobada(
        institucion: Seed.coordinador,
        ceiAprobado: false,
        consentimiento: documento,
        pruebasIntegradas: true);
    repo.incorporarTramo(tramo(1, '10'), 'preproduccion-1', 'aparato-1');
    expect(repo.config.consentimientoAprobadoPorCei, isFalse);
    expect(repo.config.pruebasIntegradas, isTrue);
    final paciente = enrolar();
    repo.registrarConsentimiento(
        autor: Seed.reclutador,
        patientId: paciente.id,
        firmaTrazos: [
          [(x: 0.1, y: 0.2), (x: 0.3, y: 0.4)]
        ]);
    expect(repo.paciente(paciente.id)!.tieneConsentimiento, isTrue);
    expect(repo.pendienteDeEnvio().pacientes, hasLength(1));
    repo.guardarConfiguracionAprobada(
        institucion: Seed.coordinador,
        ceiAprobado: false,
        consentimiento: documento);
    expect(repo.config.capturaHabilitada, isFalse);
    expect(() => enrolar(), throwsStateError);
  });

  test('sin aprobación configurada no se usa un tramo ya reservado', () {
    repo.incorporarTramo(tramo(1, '10'), 'estudio-1', 'aparato-1');
    repo.guardarAjuste('configuracion_aprobada', '');
    expect(() => enrolar(), throwsStateError);
    expect(repo.asignacionesRestantes, 2);
    expect(repo.pacientes(), isEmpty);
  });

  test('rechaza el consentimiento de demostración en producción', () {
    expect(
      () => repo.guardarConfiguracionAprobada(
        institucion: Seed.coordinador,
        ceiAprobado: true,
        consentimiento: {
          'aprobado': true,
          'version': 'demo-1',
          'codigo_cei': 'CEI pendiente',
          'vigente_desde': '2026-10-26',
          'parrafos': ['Texto inventado.'],
          'declaraciones': ['Acepto.'],
        },
      ),
      throwsStateError,
    );
  });

  test('consume solo posiciones propias y no rebobina al repetir respuesta',
      () {
    repo.incorporarTramo(tramo(26, '10'), 'estudio-1', 'aparato-1');
    final primero = enrolar();
    expect(primero.posicionSecuencia, 26);
    expect(primero.protocolo.name, 'b');

    repo.incorporarTramo(tramo(26, '10'), 'estudio-1', 'aparato-1');
    final segundo = enrolar();
    expect(segundo.posicionSecuencia, 27);
    expect(segundo.protocolo.name, 'a');
    expect(repo.asignacionesRestantes, 0);
    expect(() => enrolar(), throwsStateError);
    expect(repo.pacientes(), hasLength(2));
  });

  test('archiva el texto firmado y audita ficha y consentimiento', () {
    repo.incorporarTramo(tramo(1, '1'), 'estudio-1', 'aparato-1');
    final paciente = enrolar();
    final consentimiento = repo.registrarConsentimiento(
      autor: Seed.reclutador,
      patientId: paciente.id,
      firmaTrazos: [
        [(x: 0.1, y: 0.2), (x: 0.8, y: 0.7)]
      ],
    );
    expect(consentimiento.documentoFirmado!.parrafos,
        ['Texto inventado para pruebas.']);
    final archivo = consentimientoArchivable(consentimiento, paciente.codigo);
    expect(archivo, contains('Texto inventado para pruebas.'));
    expect(archivo, contains('<polyline'));
    final firmaFirestore =
        ConsentimientoEnviable(consentimiento).aJsonFirestore()['firma'] as Map;
    final trazosFirestore = firmaFirestore['trazos'] as List;
    expect(trazosFirestore.first, isA<Map>());
    expect((trazosFirestore.first as Map)['puntos'], hasLength(2));
    expect(repo.auditoria(entidadId: paciente.id).single.entidad.name, 'ficha');
    expect(repo.auditoria(entidadId: consentimiento.id).single.entidad.name,
        'consentimiento');
    repo.guardarConfiguracionAprobada(
      institucion: Seed.coordinador,
      ceiAprobado: true,
      consentimiento: {
        'aprobado': true,
        'version': 'prueba-2',
        'codigo_cei': 'CEI-PRUEBA',
        'vigente_desde': '2026-10-26',
        'parrafos': ['Texto posterior inventado.'],
        'declaraciones': ['Acepto la prueba posterior.'],
      },
    );
    final archivado = repo.pendienteDeEnvio().consentimientos.single;
    expect(archivado.documentoFirmado!.version, 'prueba-1');
    expect(archivado.documentoFirmado!.parrafos,
        ['Texto inventado para pruebas.']);
  });

  test('rechaza tramos distintos con la misma posición o con solape', () {
    repo.incorporarTramo(tramo(1, '01'), 'estudio-1', 'aparato-1');
    expect(() => repo.incorporarTramo(tramo(1, '11'), 'estudio-1', 'aparato-1'),
        throwsStateError);
    expect(() => repo.incorporarTramo(tramo(2, '10'), 'estudio-1', 'aparato-1'),
        throwsStateError);
  });
}
