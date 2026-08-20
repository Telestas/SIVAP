import 'dart:convert';

import 'package:sqlite3/sqlite3.dart';

import '../../core/ids.dart';
import '../../domain/models/audit_entry.dart';
import '../../domain/models/consent.dart';
import '../../domain/models/patient.dart';
import '../../domain/models/protocolo.dart';
import '../../domain/models/role.dart';
import '../../domain/models/visit.dart';
import '../../domain/repositories/study_repository.dart';
import '../allocation/allocation_strategy.dart';
import 'db/sivap_database.dart';
import 'demo_dataset.dart';
import 'seed_data.dart';

/// Implementación de [StudyRepository] sobre la base local cifrada.
///
/// Las operaciones son síncronas porque `package:sqlite3` lo es: la apertura de
/// la base es lo único asíncrono, y ocurre una vez al arrancar. Las pantallas
/// no cambian.
class SqliteStudyRepository implements StudyRepository {
  SqliteStudyRepository(this._base, {required AllocationSequence secuencia}) {
    _asegurarSecuencia(secuencia);
  }

  final SivapDatabase _base;
  Database get _db => _base.db;

  @override
  StudyConfig get config => Seed.config;

  // ── Secuencia de aleatorización ────────────────────────────────

  /// Registra la secuencia del estudio la primera vez. Si ya hay una activa,
  /// **no la sustituye**: cambiar de secuencia con pacientes ya enrolados
  /// rompería la trazabilidad de todo lo asignado hasta ese momento.
  void _asegurarSecuencia(AllocationSequence secuencia) {
    final existe = _db.select(
        'SELECT etiqueta FROM secuencia_aleatorizacion WHERE activa = 1;');
    if (existe.isNotEmpty) return;

    _db.execute(
      'INSERT INTO secuencia_aleatorizacion '
      '(etiqueta, origen, generada_en, codigo_binario, semilla, consumidas, activa) '
      'VALUES (?, ?, ?, ?, ?, 0, 1);',
      [
        secuencia.etiqueta,
        secuencia.origen.name,
        secuencia.generadaEn.toIso8601String(),
        secuencia.codigoBinario,
        secuencia.semilla,
      ],
    );
  }

  /// Reconstruye la secuencia activa desde la base, con su contador.
  ({AllocationSequence secuencia, int consumidas}) _secuenciaActiva() {
    final fila = _db
        .select('SELECT * FROM secuencia_aleatorizacion WHERE activa = 1;')
        .first;
    final codigo = fila['codigo_binario'] as String;
    return (
      secuencia: AllocationSequence(
        valores: [
          for (final c in codigo.split(''))
            c == '1' ? Protocolo.nuevo : Protocolo.vigente
        ],
        etiqueta: fila['etiqueta'] as String,
        origen: OrigenSecuencia.values
            .firstWhere((o) => o.name == fila['origen'] as String),
        generadaEn: DateTime.parse(fila['generada_en'] as String),
        semilla: fila['semilla'] as int?,
      ),
      consumidas: fila['consumidas'] as int,
    );
  }

  /// Cuántas asignaciones quedan en la secuencia activa.
  int get asignacionesRestantes {
    final s = _secuenciaActiva();
    return s.secuencia.longitud - s.consumidas;
  }

  // ── Lectura ────────────────────────────────────────────────────

  @override
  List<Patient> pacientes({String? recolectorId}) {
    final filas = recolectorId == null
        ? _db.select(_sqlPaciente)
        : _db.select('$_sqlPaciente WHERE p.recolector_id = ?;', [recolectorId]);
    final lista = filas.map(_leerPaciente).toList()
      ..sort((a, b) => a.nombre.compareTo(b.nombre));
    return lista;
  }

  @override
  Patient? paciente(String id) {
    final filas = _db.select('$_sqlPaciente WHERE p.id = ?;', [id]);
    return filas.isEmpty ? null : _leerPaciente(filas.first);
  }

  static const _sqlPaciente = '''
    SELECT p.*, i.nombre, i.carne_identidad, i.numero_historia_clinica,
           i.telefono, i.direccion
    FROM pacientes p
    JOIN identidad i ON i.paciente_id = p.id
  ''';

  Patient _leerPaciente(Row f) => Patient(
        id: f['id'] as String,
        nombre: f['nombre'] as String,
        carneIdentidad: f['carne_identidad'] as String,
        edad: f['edad'] as int,
        sexo: Sexo.values.firstWhere((s) => s.name == f['sexo'] as String),
        numeroHistoriaClinica: f['numero_historia_clinica'] as String,
        telefono: f['telefono'] as String,
        direccion: f['direccion'] as String,
        protocolo:
            Protocolo.values.firstWhere((p) => p.name == f['protocolo'] as String),
        bloqueAleatorizacion: f['secuencia_etiqueta'] as String,
        asignadoEn: DateTime.parse(f['asignado_en'] as String),
        recolectorId: f['recolector_id'] as String,
        enroladoEn: DateTime.parse(f['enrolado_en'] as String),
        consentimientoId: f['consentimiento_id'] as String?,
      );

  @override
  List<Visit> visitasDe(String patientId) => _db
      .select('SELECT * FROM visitas WHERE paciente_id = ? ORDER BY dia;',
          [patientId])
      .map(_leerVisita)
      .toList();

  @override
  Visit? visita(String patientId, int dia) {
    final filas = _db.select(
        'SELECT * FROM visitas WHERE paciente_id = ? AND dia = ?;',
        [patientId, dia]);
    return filas.isEmpty ? null : _leerVisita(filas.first);
  }

  Visit _leerVisita(Row f) => Visit(
        id: f['id'] as String,
        patientId: f['paciente_id'] as String,
        dia: f['dia'] as int,
        fechaProgramada: DateTime.parse(f['fecha_programada'] as String),
        status:
            VisitStatus.values.firstWhere((s) => s.name == f['estado'] as String),
        sync: SyncStatus.values.firstWhere((s) => s.name == f['sync'] as String),
        valores: _leerValores(f['id'] as String),
        recolectorId: f['recolector_id'] as String,
        fechaCaptura: f['fecha_captura'] == null
            ? null
            : DateTime.parse(f['fecha_captura'] as String),
        correcciones: f['correcciones'] as int,
      );

  Map<String, Object?> _leerValores(String visitaId) {
    final filas = _db.select(
        'SELECT campo, tipo, valor FROM visita_valores WHERE visita_id = ?;',
        [visitaId]);
    return {
      for (final f in filas)
        f['campo'] as String: _decodificar(f['tipo'] as String, f['valor'] as String?)
    };
  }

  @override
  List<AuditEntry> auditoria({String? entidadId, int? limite}) {
    final sql = StringBuffer('SELECT * FROM auditoria');
    final params = <Object?>[];
    if (entidadId != null) {
      sql.write(' WHERE entidad_id = ?');
      params.add(entidadId);
    }
    sql.write(' ORDER BY ocurrido_en DESC');
    if (limite != null) {
      sql.write(' LIMIT ?');
      params.add(limite);
    }
    return _db.select('$sql;', params).map(_leerAuditoria).toList();
  }

  AuditEntry _leerAuditoria(Row f) => AuditEntry(
        id: f['id'] as String,
        ocurridoEn: DateTime.parse(f['ocurrido_en'] as String),
        autorId: f['autor_id'] as String,
        autorNombre: f['autor_nombre'] as String,
        entidad: AuditEntity.values
            .firstWhere((e) => e.name == f['entidad'] as String),
        entidadId: f['entidad_id'] as String,
        descripcionObjetivo: f['descripcion_objetivo'] as String,
        campo: f['campo'] as String,
        valorAnterior: f['valor_anterior'] as String?,
        valorNuevo: f['valor_nuevo'] as String?,
        motivo: f['motivo'] as String,
      );

  @override
  int get registrosEnCola => _db
      .select("SELECT count(*) c FROM visitas WHERE sync != 'sincronizado' "
          'AND EXISTS (SELECT 1 FROM visita_valores v WHERE v.visita_id = visitas.id);')
      .first['c'] as int;

  @override
  int get dispositivosConCola => _db
      .select("SELECT count(DISTINCT recolector_id) c FROM visitas "
          "WHERE sync != 'sincronizado' "
          'AND EXISTS (SELECT 1 FROM visita_valores v WHERE v.visita_id = visitas.id);')
      .first['c'] as int;

  // ── Escritura ──────────────────────────────────────────────────

  @override
  Patient enrolar({
    required Investigador autor,
    required String nombre,
    required String carneIdentidad,
    required int edad,
    required Sexo sexo,
    required String numeroHistoriaClinica,
    required String telefono,
    required String direccion,
  }) {
    if (!autor.role.puedeEnrolar) {
      throw PermissionDenied(autor.role, 'enrolar pacientes');
    }

    // Asignación y alta van en la misma transacción. Si se guardara el paciente
    // sin avanzar el contador —o al revés— la secuencia dejaría de
    // corresponderse con los pacientes, que es un daño irreparable.
    return _enTransaccion(() {
      final estado = _secuenciaActiva();
      final estrategia = SequentialAllocation(
          secuencia: estado.secuencia, consumidas: estado.consumidas);
      final asignacion = estrategia.asignar(ahora: DateTime.now());

      _db.execute(
        'UPDATE secuencia_aleatorizacion SET consumidas = ? WHERE etiqueta = ?;',
        [estrategia.consumidas, estado.secuencia.etiqueta],
      );

      final ahora = DateTime.now();
      final id = Ids.nuevo('p');

      _db.execute(
        'INSERT INTO pacientes (id, edad, sexo, protocolo, secuencia_etiqueta, '
        'secuencia_posicion, asignado_en, recolector_id, enrolado_en) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);',
        [
          id,
          edad,
          sexo.name,
          asignacion.protocolo.name,
          asignacion.etiquetaSecuencia,
          asignacion.posicion,
          asignacion.asignadoEn.toIso8601String(),
          autor.id,
          ahora.toIso8601String(),
        ],
      );
      _db.execute(
        'INSERT INTO identidad (paciente_id, nombre, carne_identidad, '
        'numero_historia_clinica, telefono, direccion) VALUES (?, ?, ?, ?, ?, ?);',
        [id, nombre, carneIdentidad, numeroHistoriaClinica, telefono, direccion],
      );

      for (final dia in config.definicionFormulario.diasVisita) {
        _db.execute(
          'INSERT INTO visitas (id, paciente_id, dia, fecha_programada, estado, '
          'sync, recolector_id) VALUES (?, ?, ?, ?, ?, ?, ?);',
          [
            Ids.nuevo('v'),
            id,
            dia,
            DateTime(ahora.year, ahora.month, ahora.day + dia - 1)
                .toIso8601String(),
            VisitStatus.programada.name,
            SyncStatus.local.name,
            autor.id,
          ],
        );
      }

      return paciente(id)!;
    });
  }

  @override
  Consent registrarConsentimiento({
    required Investigador autor,
    required String patientId,
    required List<List<({double x, double y})>> firmaTrazos,
  }) {
    if (!autor.role.puedeEnrolar) {
      throw PermissionDenied(autor.role, 'registrar consentimientos');
    }
    final doc = config.documentoConsentimiento;
    final consent = Consent(
      id: Ids.nuevo('c'),
      patientId: patientId,
      versionDocumento: doc.version,
      codigoCei: doc.codigoCei,
      firmadoEn: DateTime.now(),
      testigoId: autor.id,
      firmaTrazos: firmaTrazos,
    );

    return _enTransaccion(() {
      _db.execute(
        'INSERT INTO consentimientos (id, paciente_id, version_documento, '
        'codigo_cei, firmado_en, testigo_id, firma_json) VALUES (?, ?, ?, ?, ?, ?, ?);',
        [
          consent.id,
          patientId,
          consent.versionDocumento,
          consent.codigoCei,
          consent.firmadoEn.toIso8601String(),
          consent.testigoId,
          _codificarFirma(firmaTrazos),
        ],
      );
      _db.execute('UPDATE pacientes SET consentimiento_id = ? WHERE id = ?;',
          [consent.id, patientId]);
      return consent;
    });
  }

  @override
  Visit guardarBorrador({
    required Investigador autor,
    required String patientId,
    required int dia,
    required Map<String, Object?> valores,
  }) =>
      _escribir(
        autor: autor,
        patientId: patientId,
        dia: dia,
        valores: valores,
        estado: VisitStatus.enCaptura,
        sync: SyncStatus.local,
      );

  @override
  Visit cerrarVisita({
    required Investigador autor,
    required String patientId,
    required int dia,
    required Map<String, Object?> valores,
  }) =>
      _escribir(
        autor: autor,
        patientId: patientId,
        dia: dia,
        valores: valores,
        estado: VisitStatus.enviada,
        sync: SyncStatus.enCola,
      );

  Visit _escribir({
    required Investigador autor,
    required String patientId,
    required int dia,
    required Map<String, Object?> valores,
    required VisitStatus estado,
    required SyncStatus sync,
  }) {
    if (!autor.role.puedeCapturarVisitas) {
      throw PermissionDenied(autor.role, 'capturar visitas');
    }
    final p = paciente(patientId)!;
    if (!p.tieneConsentimiento) {
      throw StateError(
          'No se pueden capturar visitas de ${p.nombre} sin consentimiento registrado.');
    }
    final actual = visita(patientId, dia)!;
    // Restricción CLAUDE.md §2: lo ya enviado no se sobrescribe por esta vía.
    if (actual.status.esInmutable) throw SilentEditRejected(actual.id);

    return _enTransaccion(() {
      _db.execute(
        'UPDATE visitas SET estado = ?, sync = ?, fecha_captura = ? WHERE id = ?;',
        [estado.name, sync.name, DateTime.now().toIso8601String(), actual.id],
      );
      _db.execute('DELETE FROM visita_valores WHERE visita_id = ?;', [actual.id]);
      for (final e in valores.entries) {
        if (e.value == null) continue;
        final (tipo, texto) = _codificar(e.value!);
        _db.execute(
          'INSERT INTO visita_valores (visita_id, campo, tipo, valor) '
          'VALUES (?, ?, ?, ?);',
          [actual.id, e.key, tipo, texto],
        );
      }
      return visita(patientId, dia)!;
    });
  }

  @override
  Visit corregirVisitaEnviada({
    required Investigador autor,
    required String patientId,
    required int dia,
    required String campo,
    required Object? valorNuevo,
    required String motivo,
  }) {
    if (!autor.role.puedeCorregirEnviado) {
      throw PermissionDenied(autor.role, 'corregir registros ya enviados');
    }
    if (motivo.trim().isEmpty) {
      throw ArgumentError.value(motivo, 'motivo',
          'Una corrección sin motivo es una edición silenciosa: no se admite.');
    }
    final actual = visita(patientId, dia)!;
    final p = paciente(patientId)!;
    final anterior = actual.valores[campo];

    return _enTransaccion(() {
      _db.execute('DELETE FROM visita_valores WHERE visita_id = ? AND campo = ?;',
          [actual.id, campo]);
      if (valorNuevo != null) {
        final (tipo, texto) = _codificar(valorNuevo);
        _db.execute(
          'INSERT INTO visita_valores (visita_id, campo, tipo, valor) '
          'VALUES (?, ?, ?, ?);',
          [actual.id, campo, tipo, texto],
        );
      }
      _db.execute(
        // Vuelve a la cola: el servidor debe recibir la versión corregida
        // junto con su entrada de auditoría.
        'UPDATE visitas SET sync = ?, correcciones = correcciones + 1 WHERE id = ?;',
        [SyncStatus.enCola.name, actual.id],
      );
      _db.execute(
        'INSERT INTO auditoria (id, ocurrido_en, autor_id, autor_nombre, entidad, '
        'entidad_id, descripcion_objetivo, campo, valor_anterior, valor_nuevo, motivo) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);',
        [
          Ids.nuevo('a'),
          DateTime.now().toIso8601String(),
          autor.id,
          autor.nombre,
          AuditEntity.visita.name,
          actual.id,
          '${p.apellidos} · D$dia',
          campo,
          anterior?.toString(),
          valorNuevo?.toString(),
          motivo.trim(),
        ],
      );
      return visita(patientId, dia)!;
    });
  }

  // ── Utilidades ─────────────────────────────────────────────────

  /// Ejecuta [accion] dentro de una transacción, deshaciéndola si algo falla.
  T _enTransaccion<T>(T Function() accion) {
    _db.execute('BEGIN;');
    try {
      final r = accion();
      _db.execute('COMMIT;');
      return r;
    } catch (_) {
      _db.execute('ROLLBACK;');
      rethrow;
    }
  }

  /// Los valores de visita son heterogéneos porque los campos son
  /// configurables: no se puede fijar una columna por tipo de antemano.
  static (String tipo, String texto) _codificar(Object valor) => switch (valor) {
        num n => ('numero', n.toString()),
        List l => ('lista', jsonEncode(l.map((e) => e.toString()).toList())),
        _ => ('texto', valor.toString()),
      };

  static Object? _decodificar(String tipo, String? texto) {
    if (texto == null) return null;
    return switch (tipo) {
      'numero' => num.tryParse(texto),
      'lista' => (jsonDecode(texto) as List).cast<String>(),
      _ => texto,
    };
  }

  static String _codificarFirma(List<List<({double x, double y})>> trazos) =>
      jsonEncode([
        for (final trazo in trazos)
          [
            for (final p in trazo) {'x': p.x, 'y': p.y}
          ]
      ]);

  void cerrar() => _base.cerrar();

  // ── Siembra de demostración ────────────────────────────────────

  /// Carga el juego de datos de demostración si la base está vacía.
  ///
  /// Solo se llama sobre el archivo de demostración, que es distinto del de
  /// producción. Nunca hay un paciente inventado y uno real en la misma base:
  /// no es una cuestión de disciplina, es que son ficheros diferentes.
  void sembrarDemostracionSiVacia() {
    final hay = _db.select('SELECT count(*) c FROM pacientes;').first['c'] as int;
    if (hay > 0) return;

    final dias = config.definicionFormulario.diasVisita;
    _enTransaccion(() {
      for (final d in Demo.pacientes) {
        _db.execute(
          'INSERT INTO pacientes (id, edad, sexo, protocolo, secuencia_etiqueta, '
          'secuencia_posicion, asignado_en, recolector_id, enrolado_en, '
          'consentimiento_id) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?);',
          [
            d.id,
            d.edad,
            d.sexo.name,
            d.protocolo.name,
            Seed.secuenciaAleatorizacion.etiqueta,
            Demo.pacientes.indexOf(d) + 1,
            d.enroladoEn.toIso8601String(),
            d.recolectorId,
            d.enroladoEn.toIso8601String(),
            'c-demo-${d.id}',
          ],
        );
        _db.execute(
          'INSERT INTO identidad (paciente_id, nombre, carne_identidad, '
          'numero_historia_clinica, telefono, direccion) VALUES (?, ?, ?, ?, ?, ?);',
          [d.id, d.nombre, d.carneIdentidad, d.hc, d.telefono, d.direccion],
        );
        _db.execute(
          'INSERT INTO consentimientos (id, paciente_id, version_documento, '
          'codigo_cei, firmado_en, testigo_id, firma_json) VALUES (?, ?, ?, ?, ?, ?, ?);',
          [
            'c-demo-${d.id}',
            d.id,
            config.documentoConsentimiento.version,
            config.documentoConsentimiento.codigoCei,
            d.enroladoEn.toIso8601String(),
            d.recolectorId,
            '[]',
          ],
        );

        for (var i = 0; i < dias.length; i++) {
          final visitaId = _idVisitaDemo(d.id, dias[i]);
          final fecha = DateTime(
              d.enroladoEn.year, d.enroladoEn.month, d.enroladoEn.day + dias[i] - 1);
          _db.execute(
            'INSERT INTO visitas (id, paciente_id, dia, fecha_programada, estado, '
            'sync, recolector_id, fecha_captura) VALUES (?, ?, ?, ?, ?, ?, ?, ?);',
            [
              visitaId,
              d.id,
              dias[i],
              fecha.toIso8601String(),
              d.estados[i].name,
              (d.estados[i] == VisitStatus.enviada ? d.sync : SyncStatus.local).name,
              d.recolectorId,
              d.estados[i] == VisitStatus.programada
                  ? null
                  : DateTime(fecha.year, fecha.month, fecha.day, 9, 30)
                      .toIso8601String(),
            ],
          );
          if (d.estados[i] == VisitStatus.programada) continue;
          for (final e in Demo.valores(i).entries) {
            if (e.value == null) continue;
            final (tipo, texto) = _codificar(e.value!);
            _db.execute(
              'INSERT INTO visita_valores (visita_id, campo, tipo, valor) '
              'VALUES (?, ?, ?, ?);',
              [visitaId, e.key, tipo, texto],
            );
          }
        }
      }

      for (final a in Demo.auditoria) {
        _db.execute(
          'INSERT INTO auditoria (id, ocurrido_en, autor_id, autor_nombre, entidad, '
          'entidad_id, descripcion_objetivo, campo, valor_anterior, valor_nuevo, '
          'motivo) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);',
          [
            Ids.nuevo('a'),
            a.ocurridoEn.toIso8601String(),
            a.autor.id,
            a.autor.nombre,
            a.entidad.name,
            a.dia == null ? a.pacienteId : _idVisitaDemo(a.pacienteId, a.dia!),
            a.descripcionObjetivo,
            a.campo,
            a.valorAnterior,
            a.valorNuevo,
            a.motivo,
          ],
        );
      }

      // Los pacientes de demostración también consumieron secuencia.
      _db.execute(
        'UPDATE secuencia_aleatorizacion SET consumidas = ? WHERE activa = 1;',
        [Demo.pacientes.length],
      );
      return null;
    });
  }

  static String _idVisitaDemo(String pacienteId, int dia) =>
      'v-$pacienteId-$dia';
}
