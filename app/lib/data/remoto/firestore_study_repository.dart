import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/models/audit_entry.dart';
import '../../domain/models/consent.dart';
import '../../domain/models/evento_clinico.dart';
import '../../domain/models/institucion.dart';
import '../../domain/models/patient.dart';
import '../../domain/models/protocolo.dart';
import '../../domain/models/role.dart';
import '../../domain/repositories/study_repository.dart';
import '../local/seed_data.dart';

/// Vista de solo lectura de los datos consolidados en Firestore.
///
/// Carga las colecciones que las reglas permiten al investigador autenticado y
/// las une en memoria para conservar la interfaz sincrónica de las pantallas.
/// La identidad, los datos clínicos y la asignación siguen siendo documentos
/// separados en el servidor; la unión solo existe durante esta sesión web.
class FirestoreStudyRepository extends StudyRepository {
  FirestoreStudyRepository({
    required this.investigador,
    FirebaseFirestore? firestore,
  }) : _firestore = firestore ?? FirebaseFirestore.instance;

  final Investigador investigador;
  final FirebaseFirestore _firestore;

  Future<void> registrarExportacion(String archivo) async {
    if (!investigador.puedeExportar) {
      throw StateError('Su función no permite exportar.');
    }
    await _firestore.collection('auditoria').add({
      'autor_uid': investigador.id,
      'institucion_codigo': investigador.institucion.codigo,
      'ocurrido_en': DateTime.now().toUtc().toIso8601String(),
      'entidad': AuditEntity.exportacion.name,
      'entidad_id': investigador.institucion.codigo,
      'descripcion_objetivo': investigador.institucion.codigo,
      'campo': 'archivo',
      'valor_anterior': null,
      'valor_nuevo': archivo,
      'motivo': 'Descarga solicitada desde el panel web',
    });
  }

  Future<void> registrarArchivoConsentimiento(String consentimientoId) async {
    if (!investigador.puedeEnrolar ||
        !_consentimientos.containsKey(consentimientoId)) {
      throw StateError('No puede archivar este consentimiento.');
    }
    await _firestore.collection('auditoria').add({
      'autor_uid': investigador.id,
      'institucion_codigo': investigador.institucion.codigo,
      'ocurrido_en': DateTime.now().toUtc().toIso8601String(),
      'entidad': AuditEntity.consentimiento.name,
      'entidad_id': consentimientoId,
      'descripcion_objetivo': consentimientoId,
      'campo': 'archivo',
      'valor_anterior': null,
      'valor_nuevo': 'descargado',
      'motivo': 'Copia archivable descargada desde el panel web',
    });
  }

  final Map<String, Patient> _pacientes = {};
  final Map<String, Consent> _consentimientos = {};
  final Map<String, List<EventoClinico>> _eventos = {};
  final List<AuditEntry> _auditoria = [];
  final List<Investigador> _investigadores = [];

  @override
  StudyConfig get config => _config;
  StudyConfig _config = Seed.config;

  @override
  bool get admiteEscritura => false;

  /// Descarga una instantánea coherente para la sesión actual.
  ///
  /// Todas las consultas incluyen la institución. No es solo una
  /// optimización: las reglas de Firestore rechazan una consulta que pudiera
  /// devolver documentos de otro centro.
  Future<void> cargar() async {
    final estudio = await _firestore.collection('estudios').doc('livere').get();
    if (estudio.data()?['entorno'] == 'preproduccion' &&
        estudio.data()?['captura_habilitada'] == true) {
      _config = StudyConfig(
        nombreEstudio: Seed.config.nombreEstudio,
        acronimo: Seed.config.acronimo,
        instituciones: [investigador.institucion],
        consentimientoAprobadoPorCei: false,
        permiteAcumularRoles: Seed.config.permiteAcumularRoles,
        documentoConsentimiento: Seed.config.documentoConsentimiento,
        definicionFormulario: Seed.config.definicionFormulario,
        pruebasIntegradas: true,
      );
    }
    final codigoCentro = investigador.institucion.codigo;
    Query<Map<String, dynamic>> visibles(String coleccion) {
      var consulta = _firestore
          .collection(coleccion)
          .where('institucion_codigo', isEqualTo: codigoCentro);
      if (!investigador.veCohorteCompleta) {
        consulta = consulta.where('autor_uid', isEqualTo: investigador.id);
      }
      return consulta;
    }

    final resultados = await Future.wait([
      visibles('pacientes').get(),
      visibles('eventos').get(),
      _firestore
          .collection('auditoria')
          .where('institucion_codigo', isEqualTo: codigoCentro)
          .get(),
    ]);

    final pacientes = resultados[0];
    final eventos = resultados[1];
    final auditoria = resultados[2];

    _investigadores.clear();
    if (investigador.puedeGestionarUsuarios) {
      final perfiles = await _firestore
          .collection('investigadores')
          .where('institucion_codigo', isEqualTo: codigoCentro)
          .get();
      for (final d in perfiles.docs) {
        final datos = d.data();
        final roles = (datos['roles'] as List<dynamic>? ?? const [])
            .whereType<String>()
            .map((nombre) => Rol.values.byName(nombre))
            .toSet();
        if (roles.isEmpty) continue;
        _investigadores.add(Investigador(
          id: d.id,
          usuario: _texto(datos['correo'] ?? datos['usuario'], d.id),
          nombre: _texto(datos['nombre'], 'Investigador del estudio'),
          roles: roles,
          institucion: Institucion(
            codigo: codigoCentro,
            nombre: _texto(datos['institucion_nombre'], codigoCentro),
          ),
        ));
      }
      _investigadores.sort((a, b) => a.nombre.compareTo(b.nombre));
    }

    final ids = pacientes.docs.map((d) => d.id).toList();
    final asignaciones = <String, Map<String, dynamic>>{};
    final identidades = <String, Map<String, dynamic>>{};
    final consentimientos = <String, String>{};

    // `get` por id evita abrir listados de identidad. Las reglas permiten cada
    // ficha solamente a quien tiene derecho a verla.
    final puedeVerIdentidad = investigador.roles.any(
      (r) => r == Rol.reclutador || r == Rol.investigadorPrincipal,
    );
    final puedeVerRama = investigador.veRamaAsignada;

    await Future.wait([
      for (final id in ids)
        if (puedeVerRama)
          _firestore.collection('asignaciones').doc(id).get().then((d) {
            if (d.exists) asignaciones[id] = d.data()!;
          }),
      for (final id in ids)
        if (puedeVerIdentidad)
          _firestore.collection('identidades').doc(id).get().then((d) {
            if (d.exists) identidades[id] = d.data()!;
          }),
    ]);

    if (investigador.puedeExportar &&
        puedeVerRama &&
        ids.any((id) => !asignaciones.containsKey(id))) {
      throw StateError('La cohorte tiene asignaciones incompletas; '
          'se detuvo la exportación para no etiquetar una rama errónea.');
    }

    if (puedeVerIdentidad) {
      final docs = await visibles('consentimientos').get();
      _consentimientos.clear();
      for (final d in docs.docs) {
        final datos = d.data();
        final pacienteId = datos['paciente_id'] as String?;
        if (pacienteId == null) continue;
        consentimientos[pacienteId] = d.id;
        final firmado = datos['documento_firmado'];
        if (firmado is! Map<String, dynamic>) continue;
        final firma = datos['firma'];
        if (firma is! Map<String, dynamic>) continue;
        _consentimientos[d.id] = Consent(
          id: d.id,
          patientId: pacienteId,
          versionDocumento: _texto(datos['version_documento']),
          codigoCei: _texto(datos['codigo_cei']),
          firmadoEn: _fecha(datos['firmado_en']),
          testigoId: _texto(datos['testigo_id']),
          firmaTrazos: [
            for (final trazo in (firma['trazos'] as List? ?? const []))
              [
                for (final punto in (trazo['puntos'] as List? ?? const []))
                  (
                    x: (punto['x'] as num).toDouble(),
                    y: (punto['y'] as num).toDouble()
                  ),
              ],
          ],
          documentoFirmado: ConsentDocument(
            version: _texto(firmado['version']),
            codigoCei: _texto(firmado['codigo_cei']),
            vigenteDesde: _texto(firmado['vigente_desde']),
            parrafos: List<String>.from(firmado['parrafos'] as List),
            declaraciones: List<String>.from(firmado['declaraciones'] as List),
          ),
        );
      }
    }

    _pacientes
      ..clear()
      ..addEntries(pacientes.docs.map((d) {
        final clinica = d.data();
        final identidad = identidades[d.id] ?? const <String, dynamic>{};
        final asignacion = asignaciones[d.id] ?? const <String, dynamic>{};
        return MapEntry(
          d.id,
          Patient(
            id: d.id,
            codigo: _texto(clinica['codigo'], d.id),
            nombre: _texto(identidad['nombre'], 'Identidad protegida'),
            numeroHistoriaClinica: _texto(identidad['numero_historia_clinica']),
            telefonoPrincipal: _texto(identidad['telefono_principal']),
            telefonoSecundario: identidad['telefono_secundario'] as String?,
            institucion: investigador.institucion,
            edad: _entero(clinica['edad']),
            sexo: _enumPorNombre(
              Sexo.values,
              clinica['sexo'],
              Sexo.masculino,
            ),
            protocolo: _enumPorNombre(
              Protocolo.values,
              asignacion['protocolo'],
              Protocolo.a,
            ),
            secuencia: _texto(asignacion['secuencia_etiqueta']),
            posicionSecuencia: _entero(asignacion['posicion']),
            asignadoEn: _fecha(
              asignacion['asignado_en'],
              respaldo: clinica['enrolado_en'],
            ),
            recolectorId: _texto(clinica['autor_uid']),
            enroladoEn: _fecha(clinica['enrolado_en']),
            consentimientoId: consentimientos[d.id],
          ),
        );
      }));

    _eventos.clear();
    for (final d in eventos.docs) {
      final datos = d.data();
      final pacienteId = _texto(datos['paciente_id']);
      if (!_pacientes.containsKey(pacienteId)) continue;
      final evento = EventoClinico(
        id: d.id,
        patientId: pacienteId,
        tipo: _tipoEvento(datos['tipo']),
        ocurrencia: _entero(datos['ocurrencia'], 1),
        fechaOcurrencia: _fecha(datos['fecha_ocurrencia']),
        estado: EstadoEvento.registrado,
        sync: SyncStatus.sincronizado,
        valores: _valores(datos['valores']),
        recolectorId: _texto(datos['autor_uid']),
        institucion: investigador.institucion,
        fechaCaptura: _fechaOpcional(datos['fecha_captura']),
      );
      (_eventos[pacienteId] ??= []).add(evento);
    }
    for (final lista in _eventos.values) {
      lista.sort(_cronologico);
    }

    _auditoria
      ..clear()
      ..addAll(auditoria.docs.map((d) {
        final datos = d.data();
        return AuditEntry(
          id: d.id,
          ocurridoEn: _fecha(datos['ocurrido_en']),
          autorId: _texto(datos['autor_original_id'] ?? datos['autor_uid']),
          autorNombre: _texto(
              datos['autor_original_nombre'], 'Investigador del estudio'),
          entidad: _enumPorNombre(
            AuditEntity.values,
            datos['entidad'],
            AuditEntity.evento,
          ),
          entidadId: _texto(datos['entidad_id']),
          descripcionObjetivo: _texto(datos['descripcion_objetivo']),
          campo: _texto(datos['campo']),
          valorAnterior: datos['valor_anterior']?.toString(),
          valorNuevo: datos['valor_nuevo']?.toString(),
          motivo: _texto(datos['motivo']),
        );
      }));
  }

  @override
  List<Patient> pacientes({String? recolectorId}) {
    final lista = _pacientes.values
        .where((p) => recolectorId == null || p.recolectorId == recolectorId)
        .toList()
      ..sort((a, b) => a.codigo.compareTo(b.codigo));
    return List.unmodifiable(lista);
  }

  @override
  Patient? paciente(String id) => _pacientes[id];

  @override
  Consent? consentimiento(String id) => _consentimientos[id];

  @override
  List<EventoClinico> eventosDe(String patientId) =>
      List.unmodifiable(_eventos[patientId] ?? const []);

  @override
  EventoClinico? evento(String id) {
    for (final e in _eventos.values.expand((lista) => lista)) {
      if (e.id == id) return e;
    }
    return null;
  }

  @override
  EventoClinico? borradorAbierto(String patientId, TipoEvento tipo) => null;

  @override
  List<AuditEntry> auditoria({String? entidadId, int? limite}) {
    final lista = _auditoria
        .where((a) => entidadId == null || a.entidadId == entidadId)
        .toList()
      ..sort((a, b) => b.ocurridoEn.compareTo(a.ocurridoEn));
    return List.unmodifiable(
        limite == null ? lista : lista.take(limite).toList());
  }

  @override
  List<Investigador> investigadores() => List.unmodifiable(_investigadores);

  @override
  int get registrosEnCola => 0;

  @override
  int get dispositivosConCola => 0;

  Never _soloLectura() => throw const RepositorioSoloLectura();

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
  }) =>
      _soloLectura();

  @override
  Consent registrarConsentimiento({
    required Investigador autor,
    required String patientId,
    required List<List<({double x, double y})>> firmaTrazos,
  }) =>
      _soloLectura();

  @override
  EventoClinico guardarBorrador({
    required Investigador autor,
    required String patientId,
    required TipoEvento tipo,
    required DateTime fechaOcurrencia,
    required Map<String, Object?> valores,
  }) =>
      _soloLectura();

  @override
  EventoClinico registrarEvento({
    required Investigador autor,
    required String patientId,
    required TipoEvento tipo,
    required DateTime fechaOcurrencia,
    required Map<String, Object?> valores,
  }) =>
      _soloLectura();

  @override
  EventoClinico corregirEventoRegistrado({
    required Investigador autor,
    required String eventoId,
    required String campo,
    required Object? valorNuevo,
    required String motivo,
  }) =>
      _soloLectura();

  @override
  Pendiente pendienteDeEnvio() => const Pendiente(
        pacientes: [],
        consentimientos: [],
        eventos: [],
        auditoria: [],
      );

  @override
  String? ajuste(String clave) => null;

  @override
  void guardarAjuste(String clave, String valor) => _soloLectura();

  @override
  void anotarEnviados(
          {required String loteId, required Iterable<String> ids}) =>
      _soloLectura();

  static int _cronologico(EventoClinico a, EventoClinico b) {
    final fecha = a.fechaOcurrencia.compareTo(b.fechaOcurrencia);
    if (fecha != 0) return fecha;
    final tipo = a.tipo.index.compareTo(b.tipo.index);
    return tipo != 0 ? tipo : a.ocurrencia.compareTo(b.ocurrencia);
  }

  static String _texto(Object? valor, [String respaldo = '']) =>
      valor?.toString() ?? respaldo;

  static int _entero(Object? valor, [int respaldo = 0]) => switch (valor) {
        int n => n,
        num n => n.toInt(),
        String s => int.tryParse(s) ?? respaldo,
        _ => respaldo,
      };

  static DateTime _fecha(Object? valor, {Object? respaldo}) =>
      _fechaOpcional(valor) ??
      _fechaOpcional(respaldo) ??
      DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

  static DateTime? _fechaOpcional(Object? valor) => switch (valor) {
        Timestamp t => t.toDate(),
        DateTime d => d,
        String s => DateTime.tryParse(s),
        _ => null,
      };

  static T _enumPorNombre<T extends Enum>(
      List<T> valores, Object? nombre, T respaldo) {
    for (final valor in valores) {
      if (valor.name == nombre) return valor;
    }
    return respaldo;
  }

  static TipoEvento _tipoEvento(Object? nombre) {
    final camel = _texto(nombre).replaceAllMapped(
      RegExp(r'_([a-z])'),
      (m) => m[1]!.toUpperCase(),
    );
    return _enumPorNombre(TipoEvento.values, camel, TipoEvento.enrolamiento);
  }

  static Map<String, Object?> _valores(Object? crudos) {
    if (crudos is! List) return const {};
    return Map.unmodifiable({
      for (final entrada in crudos.whereType<Map>())
        if (entrada['campo'] != null)
          entrada['campo'].toString():
              _valorTipado(entrada['valor'], entrada['tipo']),
    });
  }

  static Object? _valorTipado(Object? valor, Object? tipo) {
    if (valor == null) return null;
    final texto = valor.toString();
    return switch (tipo) {
      'siNo' || 'booleano' => texto == 'true',
      'numero' || 'entero' => num.tryParse(texto) ?? texto,
      'fecha' => DateTime.tryParse(texto) ?? texto,
      'seleccionMultiple' => texto.isEmpty ? <String>[] : texto.split(' · '),
      _ => texto,
    };
  }
}

class RepositorioSoloLectura implements Exception {
  const RepositorioSoloLectura();

  @override
  String toString() =>
      'El panel web es de solo lectura. La captura se realiza en la app móvil cifrada.';
}
