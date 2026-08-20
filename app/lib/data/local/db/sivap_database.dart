import 'dart:ffi';

import 'package:sqlcipher_flutter_libs/sqlcipher_flutter_libs.dart';
import 'package:sqlite3/open.dart';
import 'package:sqlite3/sqlite3.dart';

/// Base de datos local cifrada (SQLite + SQLCipher).
///
/// Se escribe el SQL a mano en vez de usar un generador de código. Razones,
/// para que nadie lo "modernice" sin saberlas:
///
/// - El esquema y las migraciones de un sistema que guarda datos clínicos
///   tienen que poder leerse tal cual, sin compilar nada. Aquí se leen.
/// - Un paso menos (`build_runner`) en un equipo sin desarrollador dedicado.
///
/// Si más adelante se prefiere Drift, se monta encima: las pantallas hablan con
/// `StudyRepository`, no con esta clase.
class SivapDatabase {
  SivapDatabase._(this.db);

  final Database db;

  /// Versión del esquema. Subirla obliga a añadir su migración en [_migrar].
  static const int versionEsquema = 1;

  /// Abre la base cifrada en [ruta] con [claveHex] (64 caracteres hex).
  ///
  /// Lanza [CifradoNoDisponible] si la biblioteca cargada no es SQLCipher.
  /// Esa comprobación no es paranoia: si por un fallo de empaquetado se cargara
  /// SQLite normal, `PRAGMA key` se ignora en silencio y la base quedaría en
  /// claro sin que nada avisara. Datos de salud identificables en claro, y
  /// nadie enterándose. Por eso se verifica y se aborta.
  static SivapDatabase abrir({required String ruta, required String claveHex}) {
    _registrarBibliotecaCifrada();

    final db = sqlite3.open(ruta);
    try {
      // Clave en bruto: los 32 bytes se usan tal cual, sin derivación.
      db.execute('PRAGMA key = "x\'$claveHex\'";');

      _verificarCifrado(db);

      // Toca la base para que la clave se valide de verdad. Con una clave
      // incorrecta, esta lectura falla; sin ella, el error aparecería mucho
      // más tarde y en un sitio confuso.
      db.select('SELECT count(*) FROM sqlite_schema;');

      db.execute('PRAGMA foreign_keys = ON;');
      // WAL: la captura en sala no puede quedarse esperando a que termine una
      // lectura del listado.
      db.execute('PRAGMA journal_mode = WAL;');

      _migrar(db);
      return SivapDatabase._(db);
    } catch (_) {
      db.dispose();
      rethrow;
    }
  }

  static void _registrarBibliotecaCifrada() {
    open
      ..overrideFor(OperatingSystem.android, openCipherOnAndroid)
      ..overrideFor(OperatingSystem.iOS, () => DynamicLibrary.process())
      ..overrideFor(OperatingSystem.macOS, () => DynamicLibrary.process());
  }

  static void _verificarCifrado(Database db) {
    try {
      final r = db.select('PRAGMA cipher_version;');
      if (r.isEmpty || (r.first.values.first?.toString() ?? '').isEmpty) {
        throw const CifradoNoDisponible();
      }
    } on SqliteException {
      throw const CifradoNoDisponible();
    }
  }

  // ── Esquema ──────────────────────────────────────────────────────
  //
  // Dos tablas para el paciente, no una, y es a propósito (BASES §8):
  //
  //   identidad  → nombre, carné, historia clínica, teléfono, dirección
  //   pacientes  → edad, sexo, rama asignada, recolector, fechas
  //
  // El dataset que se manda a analizar sale de `pacientes` + `visitas` sin
  // tocar `identidad`. La separación no es un adorno: es lo que permite
  // compartir los datos clínicos sin exponer a nadie.

  static void _migrar(Database db) {
    final actual = db.select('PRAGMA user_version;').first.values.first as int;
    if (actual >= versionEsquema) return;

    db.execute('BEGIN;');
    try {
      if (actual < 1) _crearVersion1(db);
      db.execute('PRAGMA user_version = $versionEsquema;');
      db.execute('COMMIT;');
    } catch (_) {
      db.execute('ROLLBACK;');
      rethrow;
    }
  }

  static void _crearVersion1(Database db) {
    db.execute('''
      CREATE TABLE pacientes (
        id                  TEXT PRIMARY KEY,
        edad                INTEGER NOT NULL,
        sexo                TEXT    NOT NULL,
        protocolo           TEXT    NOT NULL,
        secuencia_etiqueta  TEXT    NOT NULL,
        secuencia_posicion  INTEGER NOT NULL,
        asignado_en         TEXT    NOT NULL,
        recolector_id       TEXT    NOT NULL,
        enrolado_en         TEXT    NOT NULL,
        consentimiento_id   TEXT
      );
    ''');

    db.execute('''
      CREATE TABLE identidad (
        paciente_id             TEXT PRIMARY KEY
                                REFERENCES pacientes(id) ON DELETE CASCADE,
        nombre                  TEXT NOT NULL,
        carne_identidad         TEXT NOT NULL,
        numero_historia_clinica TEXT NOT NULL,
        telefono                TEXT NOT NULL,
        direccion               TEXT NOT NULL
      );
    ''');

    db.execute('''
      CREATE TABLE visitas (
        id               TEXT PRIMARY KEY,
        paciente_id      TEXT    NOT NULL REFERENCES pacientes(id) ON DELETE CASCADE,
        dia              INTEGER NOT NULL,
        fecha_programada TEXT    NOT NULL,
        estado           TEXT    NOT NULL,
        sync             TEXT    NOT NULL,
        recolector_id    TEXT    NOT NULL,
        fecha_captura    TEXT,
        correcciones     INTEGER NOT NULL DEFAULT 0,
        UNIQUE (paciente_id, dia)
      );
    ''');

    // Un valor por fila, no un JSON por visita: los campos del formulario son
    // configurables, así que las columnas no se pueden fijar de antemano. Así
    // además se puede exportar campo a campo y auditar uno solo.
    db.execute('''
      CREATE TABLE visita_valores (
        visita_id TEXT NOT NULL REFERENCES visitas(id) ON DELETE CASCADE,
        campo     TEXT NOT NULL,
        tipo      TEXT NOT NULL,
        valor     TEXT,
        PRIMARY KEY (visita_id, campo)
      );
    ''');

    db.execute('''
      CREATE TABLE consentimientos (
        id                TEXT PRIMARY KEY,
        paciente_id       TEXT NOT NULL REFERENCES pacientes(id) ON DELETE CASCADE,
        version_documento TEXT NOT NULL,
        codigo_cei        TEXT NOT NULL,
        firmado_en        TEXT NOT NULL,
        testigo_id        TEXT NOT NULL,
        firma_json        TEXT NOT NULL
      );
    ''');

    db.execute('''
      CREATE TABLE auditoria (
        id                   TEXT PRIMARY KEY,
        ocurrido_en          TEXT NOT NULL,
        autor_id             TEXT NOT NULL,
        autor_nombre         TEXT NOT NULL,
        entidad              TEXT NOT NULL,
        entidad_id           TEXT NOT NULL,
        descripcion_objetivo TEXT NOT NULL,
        campo                TEXT NOT NULL,
        valor_anterior       TEXT,
        valor_nuevo          TEXT,
        motivo               TEXT NOT NULL CHECK (length(trim(motivo)) > 0)
      );
    ''');

    // La auditoría es solo-añadir, y lo impone la base de datos.
    //
    // La restricción de CLAUDE.md §2 ya se comprueba en el repositorio, pero un
    // repositorio se puede reescribir mal. Estos disparadores hacen que ni
    // siquiera un UPDATE escrito a mano contra el archivo pueda alterar el
    // historial. Un registro de auditoría que se puede editar no es un
    // registro de auditoría.
    db.execute('''
      CREATE TRIGGER auditoria_sin_update
      BEFORE UPDATE ON auditoria
      BEGIN
        SELECT RAISE(ABORT, 'El registro de auditoría no admite modificaciones');
      END;
    ''');
    db.execute('''
      CREATE TRIGGER auditoria_sin_delete
      BEFORE DELETE ON auditoria
      BEGIN
        SELECT RAISE(ABORT, 'El registro de auditoría no admite borrado');
      END;
    ''');

    // Estado de la secuencia de aleatorización.
    //
    // `consumidas` vive aquí y no en memoria por una razón que no es menor: si
    // el contador se reiniciara al abrir la app, el paciente siguiente
    // recibiría la posición 1 otra vez y la aleatorización quedaría destruida
    // sin que nadie lo notara.
    db.execute('''
      CREATE TABLE secuencia_aleatorizacion (
        etiqueta       TEXT PRIMARY KEY,
        origen         TEXT    NOT NULL,
        generada_en    TEXT    NOT NULL,
        codigo_binario TEXT    NOT NULL,
        semilla        INTEGER,
        consumidas     INTEGER NOT NULL DEFAULT 0,
        activa         INTEGER NOT NULL DEFAULT 1
      );
    ''');

    db.execute(
        'CREATE INDEX idx_visitas_paciente ON visitas (paciente_id, dia);');
    db.execute(
        'CREATE INDEX idx_visitas_sync ON visitas (sync);');
    db.execute(
        'CREATE INDEX idx_auditoria_entidad ON auditoria (entidad_id, ocurrido_en);');
  }

  void cerrar() => db.dispose();
}

/// La biblioteca cargada no es SQLCipher: la base quedaría sin cifrar.
class CifradoNoDisponible implements Exception {
  const CifradoNoDisponible();

  @override
  String toString() =>
      'La base de datos no está cifrada: no se cargó SQLCipher. La app no debe '
      'guardar datos de pacientes en estas condiciones. Revise que '
      'sqlcipher_flutter_libs esté incluido en la compilación.';
}
