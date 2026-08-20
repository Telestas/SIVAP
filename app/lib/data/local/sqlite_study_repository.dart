import 'dart:convert';

import 'package:sqlite3/sqlite3.dart';

import '../../core/ids.dart';
import '../../domain/models/audit_entry.dart';
import '../../domain/models/consent.dart';
import '../../domain/models/evento_clinico.dart';
import '../../domain/models/institucion.dart';
import '../../domain/models/patient.dart';
import '../../domain/models/protocolo.dart';
import '../../domain/models/role.dart';
import '../../domain/repositories/study_repository.dart';
import '../allocation/allocation_strategy.dart';
import 'db/sivap_database.dart';
import 'demo_dataset.dart';
import 'seed_data.dart';

/// Implementación de [StudyRepository] sobre la base local cifrada.
///
/// Las operaciones son síncronas porque `package:sqlite3` lo es: la apertura de
/// la base es lo único asíncrono, y ocurre una vez al arrancar.
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

  ({AllocationSequence secuencia, int consumidas}) _secuenciaActiva() {
    final fila = _db
        .select('SELECT * FROM secuencia_aleatorizacion WHERE activa = 1;')
        .first;
    final codigo = fila['codigo_binario'] as String;
    return (
      secuencia: AllocationSequence(
        valores: [
          for (final c in codigo.split(''))
            c == '1' ? Protocolo.b : Protocolo.a
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

  static const _sqlPaciente = '''
    SELECT p.*, i.nombre, i.numero_historia_clinica,
           i.telefono_principal, i.telefono_secundario
    FROM pacientes p
    JOIN identidad i ON i.paciente_id = p.id
  ''';

  @override
  List<Patient> pacientes({String? recolectorId}) {
    final filas = recolectorId == null
        ? _db.select(_sqlPaciente)
        : _db.select('$_sqlPaciente WHERE p.recolector_id = ?;', [recolectorId]);
    final lista = filas.map(_leerPaciente).toList()
      ..sort((a, b) => a.codigo.compareTo(b.codigo));
    return lista;
  }

  @override
  Patient? paciente(String id) {
    final filas = _db.select('$_sqlPaciente WHERE p.id = ?;', [id]);
    return filas.isEmpty ? null : _leerPaciente(filas.first);
  }

  Patient _leerPaciente(Row f) => Patient(
        id: f['id'] as String,
        codigo: f['codigo'] as String,
        nombre: f['nombre'] as String,
        numeroHistoriaClinica: f['numero_historia_clinica'] as String,
        telefonoPrincipal: f['telefono_principal'] as String,
        telefonoSecundario: f['telefono_secundario'] as String?,
        institucion: _institucion(f['institucion'] as String),
        edad: f['edad'] as int,
        sexo: Sexo.values.firstWhere((s) => s.name == f['sexo'] as String),
        protocolo: Protocolo.values
            .firstWhere((p) => p.name == f['protocolo'] as String),
        secuencia: f['secuencia_etiqueta'] as String,
        posicionSecuencia: f['secuencia_posicion'] as int,
        asignadoEn: DateTime.parse(f['asignado_en'] as String),
        recolectorId: f['recolector_id'] as String,
        enroladoEn: DateTime.parse(f['enrolado_en'] as String),
        consentimientoId: f['consentimiento_id'] as String?,
      );

  /// Resuelve el código de centro contra el catálogo de la configuración.
  ///
  /// Si un registro llega con un centro que la configuración ya no declara —al
  /// sincronizar desde un dispositivo con catálogo viejo— se conserva el código
  /// en vez de perderlo: un dato clínico huérfano es preferible a un dato
  /// clínico borrado.
  Institucion _institucion(String codigo) => config.instituciones.firstWhere(
        (i) => i.codigo == codigo,
        orElse: () => Institucion(codigo: codigo, nombre: 'Centro $codigo'),
      );

  @override
  List<EventoClinico> eventosDe(String patientId) => _db
      .select(
          'SELECT * FROM eventos WHERE paciente_id = ? '
          'ORDER BY fecha_ocurrencia, tipo, ocurrencia;',
          [patientId])
      .map(_leerEvento)
      .toList();

  @override
  EventoClinico? evento(String id) {
    final filas = _db.select('SELECT * FROM eventos WHERE id = ?;', [id]);
    return filas.isEmpty ? null : _leerEvento(filas.first);
  }

  @override
  EventoClinico? borradorAbierto(String patientId, TipoEvento tipo) {
    final filas = _db.select(
      'SELECT * FROM eventos WHERE paciente_id = ? AND tipo = ? '
      "AND estado = 'borrador';",
      [patientId, tipo.name],
    );
    return filas.isEmpty ? null : _leerEvento(filas.first);
  }

  EventoClinico _leerEvento(Row f) => EventoClinico(
        id: f['id'] as String,
        patientId: f['paciente_id'] as String,
        tipo: TipoEvento.values.firstWhere((t) => t.name == f['tipo'] as String),
        ocurrencia: f['ocurrencia'] as int,
        fechaOcurrencia: DateTime.parse(f['fecha_ocurrencia'] as String),
        estado: EstadoEvento.values
            .firstWhere((e) => e.name == f['estado'] as String),
        sync: SyncStatus.values.firstWhere((s) => s.name == f['sync'] as String),
        valores: _leerValores(f['id'] as String),
        recolectorId: f['recolector_id'] as String,
        institucion: _institucion(f['institucion'] as String),
        fechaCaptura: f['fecha_captura'] == null
            ? null
            : DateTime.parse(f['fecha_captura'] as String),
        correcciones: f['correcciones'] as int,
      );

  Map<String, Object?> _leerValores(String eventoId) {
    final filas = _db.select(
        'SELECT campo, tipo, valor FROM evento_valores WHERE evento_id = ?;',
        [eventoId]);
    return {
      for (final f in filas)
        f['campo'] as String:
            _decodificar(f['tipo'] as String, f['valor'] as String?)
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

  static const _sqlConValores =
      'AND EXISTS (SELECT 1 FROM evento_valores v WHERE v.evento_id = eventos.id)';

  @override
  int get registrosEnCola => _db
      .select("SELECT count(*) c FROM eventos WHERE sync != 'sincronizado' "
          '$_sqlConValores;')
      .first['c'] as int;

  @override
  int get dispositivosConCola => _db
      .select('SELECT count(DISTINCT recolector_id) c FROM eventos '
          "WHERE sync != 'sincronizado' $_sqlConValores;")
      .first['c'] as int;

  // ── Escritura ──────────────────────────────────────────────────

  @override
  Patient enrolar({
    required Investigador autor,
    required Institucion institucion,
    required String nombre,
    required String numeroHistoriaClinica,
    required String telefonoPrincipal,
    required int edad,
    required Sexo sexo,
    String? telefonoSecundario,
  }) {
    if (!autor.puedeEnrolar) {
      throw PermissionDenied(autor, 'enrolar pacientes');
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
        'INSERT INTO pacientes (id, codigo, institucion, edad, sexo, protocolo, '
        'secuencia_etiqueta, secuencia_posicion, asignado_en, recolector_id, '
        'enrolado_en) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);',
        [
          id,
          _siguienteCodigo(institucion),
          institucion.codigo,
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
        'INSERT INTO identidad (paciente_id, nombre, numero_historia_clinica, '
        'telefono_principal, telefono_secundario) VALUES (?, ?, ?, ?, ?);',
        [id, nombre, numeroHistoriaClinica, telefonoPrincipal, telefonoSecundario],
      );

      // Sin calendario que pre-crear: los eventos aparecen cuando ocurren
      // (CLAUDE.md §4).
      return paciente(id)!;
    });
  }

  /// Correlativo por centro: «HC-004».
  ///
  /// Cuidado: sin conexión, dos dispositivos del mismo centro pueden emitir el
  /// mismo código hasta que sincronicen. Es molesto pero no corrompe nada, la
  /// clave real es el identificador aleatorio.
  String _siguienteCodigo(Institucion institucion) {
    final n = _db.select(
        'SELECT count(*) c FROM pacientes WHERE institucion = ?;',
        [institucion.codigo]).first['c'] as int;
    return '${institucion.codigo}-${(n + 1).toString().padLeft(3, '0')}';
  }

  @override
  Consent registrarConsentimiento({
    required Investigador autor,
    required String patientId,
    required List<List<({double x, double y})>> firmaTrazos,
  }) {
    if (!autor.puedeEnrolar) {
      throw PermissionDenied(autor, 'registrar consentimientos');
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
        'codigo_cei, firmado_en, testigo_id, firma_json) '
        'VALUES (?, ?, ?, ?, ?, ?, ?);',
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
  EventoClinico guardarBorrador({
    required Investigador autor,
    required String patientId,
    required TipoEvento tipo,
    required DateTime fechaOcurrencia,
    required Map<String, Object?> valores,
  }) =>
      _escribir(
        autor: autor,
        patientId: patientId,
        tipo: tipo,
        fechaOcurrencia: fechaOcurrencia,
        valores: valores,
        estado: EstadoEvento.borrador,
        sync: SyncStatus.local,
      );

  @override
  EventoClinico registrarEvento({
    required Investigador autor,
    required String patientId,
    required TipoEvento tipo,
    required DateTime fechaOcurrencia,
    required Map<String, Object?> valores,
  }) =>
      _escribir(
        autor: autor,
        patientId: patientId,
        tipo: tipo,
        fechaOcurrencia: fechaOcurrencia,
        valores: valores,
        estado: EstadoEvento.registrado,
        sync: SyncStatus.enCola,
      );

  EventoClinico _escribir({
    required Investigador autor,
    required String patientId,
    required TipoEvento tipo,
    required DateTime fechaOcurrencia,
    required Map<String, Object?> valores,
    required EstadoEvento estado,
    required SyncStatus sync,
  }) {
    // No es un permiso administrativo: es la separación de funciones que el
    // cegamiento exige (BASES §4).
    if (!autor.puedeCapturar(tipo)) throw FueraDeSuFuncion(autor, tipo);

    final p = paciente(patientId)!;
    if (!p.tieneConsentimiento) {
      throw StateError(
          'No se pueden capturar eventos de ${p.codigo} sin consentimiento '
          'registrado.');
    }
    // Un hito no repetible que ya se registró no se duplica: se corrige, y la
    // corrección deja rastro (CLAUDE.md §3).
    if (!tipo.repetible && _yaRegistrado(patientId, tipo)) {
      throw EventoNoRepetible(tipo);
    }

    return _enTransaccion(() {
      final abierto = borradorAbierto(patientId, tipo);
      final id = abierto?.id ?? Ids.nuevo('e');

      if (abierto == null) {
        _db.execute(
          'INSERT INTO eventos (id, paciente_id, tipo, ocurrencia, '
          'fecha_ocurrencia, estado, sync, recolector_id, institucion, '
          'fecha_captura) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?);',
          [
            id,
            patientId,
            tipo.name,
            _siguienteOcurrencia(patientId, tipo),
            fechaOcurrencia.toIso8601String(),
            estado.name,
            sync.name,
            autor.id,
            autor.institucion.codigo,
            DateTime.now().toIso8601String(),
          ],
        );
      } else {
        _db.execute(
          'UPDATE eventos SET estado = ?, sync = ?, fecha_ocurrencia = ?, '
          'fecha_captura = ? WHERE id = ?;',
          [
            estado.name,
            sync.name,
            fechaOcurrencia.toIso8601String(),
            DateTime.now().toIso8601String(),
            id,
          ],
        );
      }

      _db.execute('DELETE FROM evento_valores WHERE evento_id = ?;', [id]);
      for (final e in valores.entries) {
        if (e.value == null) continue;
        final (tipoValor, texto) = _codificar(e.value!);
        _db.execute(
          'INSERT INTO evento_valores (evento_id, campo, tipo, valor) '
          'VALUES (?, ?, ?, ?);',
          [id, e.key, tipoValor, texto],
        );
      }
      return evento(id)!;
    });
  }

  bool _yaRegistrado(String patientId, TipoEvento tipo) =>
      (_db.select(
              'SELECT count(*) c FROM eventos WHERE paciente_id = ? '
              "AND tipo = ? AND estado = 'registrado';",
              [patientId, tipo.name]).first['c'] as int) >
      0;

  int _siguienteOcurrencia(String patientId, TipoEvento tipo) =>
      (_db.select(
              'SELECT count(*) c FROM eventos WHERE paciente_id = ? AND tipo = ?;',
              [patientId, tipo.name]).first['c'] as int) +
      1;

  @override
  EventoClinico corregirEventoRegistrado({
    required Investigador autor,
    required String eventoId,
    required String campo,
    required Object? valorNuevo,
    required String motivo,
  }) {
    if (!autor.puedeCorregirRegistrado) {
      throw PermissionDenied(autor, 'corregir registros ya enviados');
    }
    if (motivo.trim().isEmpty) {
      throw ArgumentError.value(motivo, 'motivo',
          'Una corrección sin motivo es una edición silenciosa: no se admite.');
    }
    final actual = evento(eventoId)!;
    final p = paciente(actual.patientId)!;
    final anterior = actual.valores[campo];

    return _enTransaccion(() {
      _db.execute('DELETE FROM evento_valores WHERE evento_id = ? AND campo = ?;',
          [eventoId, campo]);
      if (valorNuevo != null) {
        final (tipoValor, texto) = _codificar(valorNuevo);
        _db.execute(
          'INSERT INTO evento_valores (evento_id, campo, tipo, valor) '
          'VALUES (?, ?, ?, ?);',
          [eventoId, campo, tipoValor, texto],
        );
      }
      _db.execute(
        // Vuelve a la cola: el servidor debe recibir la versión corregida junto
        // con su entrada de auditoría.
        'UPDATE eventos SET sync = ?, correcciones = correcciones + 1 '
        'WHERE id = ?;',
        [SyncStatus.enCola.name, eventoId],
      );
      _db.execute(
        'INSERT INTO auditoria (id, ocurrido_en, autor_id, autor_nombre, '
        'entidad, entidad_id, descripcion_objetivo, campo, valor_anterior, '
        'valor_nuevo, motivo) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);',
        [
          Ids.nuevo('a'),
          DateTime.now().toIso8601String(),
          autor.id,
          autor.nombre,
          AuditEntity.evento.name,
          eventoId,
          '${p.codigo} · ${actual.referenciaCorta}',
          campo,
          anterior?.toString(),
          valorNuevo?.toString(),
          motivo.trim(),
        ],
      );
      return evento(eventoId)!;
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

  /// Los valores son heterogéneos porque los campos son configurables: no se
  /// puede fijar una columna por tipo de antemano.
  static (String tipo, String texto) _codificar(Object valor) => switch (valor) {
        bool b => ('booleano', b ? '1' : '0'),
        num n => ('numero', n.toString()),
        List l => ('lista', jsonEncode(l.map((e) => e.toString()).toList())),
        _ => ('texto', valor.toString()),
      };

  static Object? _decodificar(String tipo, String? texto) {
    if (texto == null) return null;
    return switch (tipo) {
      'booleano' => texto == '1',
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

    _enTransaccion(() {
      for (final d in Demo.pacientes) {
        _db.execute(
          'INSERT INTO pacientes (id, codigo, institucion, edad, sexo, '
          'protocolo, secuencia_etiqueta, secuencia_posicion, asignado_en, '
          'recolector_id, enrolado_en, consentimiento_id) '
          'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);',
          [
            d.id,
            d.codigo,
            d.institucion.codigo,
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
          'INSERT INTO identidad (paciente_id, nombre, '
          'numero_historia_clinica, telefono_principal) VALUES (?, ?, ?, ?);',
          [d.id, d.nombre, d.hc, d.telefono],
        );
        _db.execute(
          'INSERT INTO consentimientos (id, paciente_id, version_documento, '
          'codigo_cei, firmado_en, testigo_id, firma_json) '
          'VALUES (?, ?, ?, ?, ?, ?, ?);',
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

        final porTipo = <TipoEvento, int>{};
        for (final ev in d.eventos) {
          final ocurrencia = (porTipo[ev.tipo] = (porTipo[ev.tipo] ?? 0) + 1);
          final id = idEventoDemo(d.id, ev.tipo, ocurrencia);
          final fecha =
              d.enroladoEn.add(Duration(days: ev.diaDesdeEnrolamiento));
          _db.execute(
            'INSERT INTO eventos (id, paciente_id, tipo, ocurrencia, '
            'fecha_ocurrencia, estado, sync, recolector_id, institucion, '
            'fecha_captura) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?);',
            [
              id,
              d.id,
              ev.tipo.name,
              ocurrencia,
              fecha.toIso8601String(),
              (ev.borrador ? EstadoEvento.borrador : EstadoEvento.registrado)
                  .name,
              (ev.borrador ? SyncStatus.local : d.sync).name,
              ev.recolectorId ?? d.recolectorId,
              d.institucion.codigo,
              DateTime(fecha.year, fecha.month, fecha.day, 9, 30)
                  .toIso8601String(),
            ],
          );
          for (final e in ev.valores.entries) {
            if (e.value == null) continue;
            final (tipoValor, texto) = _codificar(e.value!);
            _db.execute(
              'INSERT INTO evento_valores (evento_id, campo, tipo, valor) '
              'VALUES (?, ?, ?, ?);',
              [id, e.key, tipoValor, texto],
            );
          }
        }
      }

      for (final a in Demo.auditoria) {
        _db.execute(
          'INSERT INTO auditoria (id, ocurrido_en, autor_id, autor_nombre, '
          'entidad, entidad_id, descripcion_objetivo, campo, valor_anterior, '
          'valor_nuevo, motivo) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);',
          [
            Ids.nuevo('a'),
            a.ocurridoEn.toIso8601String(),
            a.autor.id,
            a.autor.nombre,
            AuditEntity.evento.name,
            idEventoDemo(a.pacienteId, a.tipo, a.ocurrencia),
            '${Demo.porId(a.pacienteId).codigo} · ${a.tipo.etiqueta}',
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

  static String idEventoDemo(
          String pacienteId, TipoEvento tipo, int ocurrencia) =>
      'e-$pacienteId-${tipo.name}-$ocurrencia';
}
