import 'dart:ffi';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/open.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:sivap/data/local/db/sivap_database.dart';

/// El esquema de la base del dispositivo, contra un SQLite de verdad.
///
/// Hasta aquí, el esquema local solo se comprobaba arrancando la app en un
/// teléfono: si una sentencia estaba mal, se descubría instalando. Estas
/// pruebas lo crean en memoria y le hacen las mismas consultas que hace el
/// repositorio.
///
/// **Sin SQLCipher**: aquí se usa el SQLite del sistema, que no cifra. Lo que
/// se comprueba es la *forma* del esquema, no el cifrado — eso sigue siendo
/// cosa del teléfono, y `docs/PENDIENTE.md` lo tiene anotado.
void main() {
  late Database db;

  setUpAll(() {
    open.overrideFor(OperatingSystem.linux, _abrirDelSistema);
  });

  setUp(() {
    db = sqlite3.openInMemory();
    SivapDatabase.aplicarEsquema(db);
  });

  tearDown(() => db.dispose());

  test('el esquema se crea entero desde cero', () {
    final tablas = db
        .select("SELECT name FROM sqlite_master WHERE type = 'table' "
            "AND name NOT LIKE 'sqlite_%' ORDER BY name;")
        .map((f) => f['name'] as String)
        .toList();

    expect(
      tablas,
      containsAll([
        'auditoria',
        'consentimientos',
        'enviados',
        'eventos',
        'evento_valores',
        'identidad',
        'pacientes',
      ]),
    );
  });

  test('queda anotada la versión del esquema', () {
    expect(db.select('PRAGMA user_version;').first['user_version'],
        SivapDatabase.versionEsquema);
  });

  test('una base vieja se migra sin perder lo que tenía', () {
    // El caso que va a ocurrir en los teléfonos que ya tienen la app: la base
    // está en la versión 1 y hay que añadirle lo nuevo sin tocar los datos.
    final vieja = sqlite3.openInMemory();
    SivapDatabase.aplicarEsquema(vieja);
    vieja.execute('DROP TABLE enviados;');
    vieja.execute('PRAGMA user_version = 1;');
    vieja.execute(
        'INSERT INTO pacientes (id, codigo, institucion, edad, sexo, protocolo,'
        ' secuencia_etiqueta, secuencia_posicion, asignado_en, recolector_id,'
        " enrolado_en) VALUES ('p1','HC-001','HC',60,'masculino','a','s',1,"
        "'2026-01-01','u1','2026-01-01');");

    SivapDatabase.aplicarEsquema(vieja);

    expect(vieja.select('SELECT count(*) c FROM pacientes;').first['c'], 1);
    expect(vieja.select('SELECT count(*) c FROM enviados;').first['c'], 0);
    expect(vieja.select('PRAGMA user_version;').first['user_version'],
        SivapDatabase.versionEsquema);
    vieja.dispose();
  });

  test('dos borradores del mismo hito no pueden coexistir', () {
    // No es disciplina del repositorio: lo impide la propia base. Dos
    // borradores simultáneos serían dos versiones del mismo dato compitiendo.
    db.execute(
        'INSERT INTO pacientes (id, codigo, institucion, edad, sexo, protocolo,'
        ' secuencia_etiqueta, secuencia_posicion, asignado_en, recolector_id,'
        " enrolado_en) VALUES ('p1','HC-001','HC',60,'masculino','a','s',1,"
        "'2026-01-01','u1','2026-01-01');");
    void borrador(String id) => db.execute(
        'INSERT INTO eventos (id, paciente_id, tipo, ocurrencia,'
        ' fecha_ocurrencia, estado, sync, recolector_id, institucion)'
        " VALUES ('$id','p1','cribado',1,'2026-01-02','borrador','local',"
        "'u1','HC');");

    borrador('e1');

    expect(() => borrador('e2'), throwsA(isA<SqliteException>()));
  });

  test('una corrección sin motivo no cabe en la tabla de auditoría', () {
    // La regla vive en la base y no solo en el repositorio (CLAUDE.md §3).
    expect(
      () => db.execute(
          'INSERT INTO auditoria (id, ocurrido_en, autor_id, autor_nombre,'
          ' entidad, entidad_id, descripcion_objetivo, campo, motivo)'
          " VALUES ('a1','2026-01-01','u1','Dra. Uno','evento','e1','x','y','  ');"),
      throwsA(isA<SqliteException>()),
    );
  });

  test('las consultas de la cola de envío casan con el esquema', () {
    // Si una columna se renombra, esto falla aquí y no en el teléfono.
    for (final consulta in [
      'SELECT p.*, i.nombre, i.numero_historia_clinica, i.telefono_principal,'
          ' i.telefono_secundario FROM pacientes p'
          ' JOIN identidad i ON i.paciente_id = p.id'
          ' WHERE p.id NOT IN (SELECT id FROM enviados);',
      'SELECT * FROM consentimientos WHERE id NOT IN (SELECT id FROM enviados);',
      "SELECT * FROM eventos WHERE estado = 'registrado'"
          ' AND id NOT IN (SELECT id FROM enviados);',
      'SELECT * FROM auditoria WHERE id NOT IN (SELECT id FROM enviados);',
    ]) {
      expect(() => db.select(consulta), returnsNormally, reason: consulta);
    }
  });

  test('un acuse repetido actualiza, no duplica', () {
    void acusar(String lote) => db.execute(
        "INSERT INTO enviados (id, lote_id, enviado_en) VALUES ('x','$lote','h')"
        ' ON CONFLICT(id) DO UPDATE SET lote_id = excluded.lote_id,'
        ' enviado_en = excluded.enviado_en;');

    acusar('lote-1');
    acusar('lote-2');

    final filas = db.select('SELECT * FROM enviados;');
    expect(filas, hasLength(1));
    expect(filas.first['lote_id'], 'lote-2');
  });
}

/// El SQLite del sistema. En el teléfono lo pone `sqlcipher_flutter_libs`; aquí
/// no hace falta cifrar para comprobar la forma del esquema.
DynamicLibrary _abrirDelSistema() {
  for (final nombre in ['libsqlite3.so.0', 'libsqlite3.so']) {
    try {
      return DynamicLibrary.open(nombre);
    } on ArgumentError {
      continue;
    }
  }
  throw StateError('No se encontró libsqlite3 en el sistema.');
}
