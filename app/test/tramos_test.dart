import 'dart:ffi';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/open.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:sivap/data/local/db/sivap_database.dart';
import 'package:sivap/data/local/sqlite_study_repository.dart';
import 'package:sivap/data/local/seed_data.dart';
import 'package:sivap/data/exportacion/consentimiento_archivable.dart';
import 'package:sivap/data/remoto/lote.dart';
import 'package:sivap/domain/models/patient.dart';

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
