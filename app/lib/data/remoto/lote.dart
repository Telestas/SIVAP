import '../../core/ids.dart';
import '../../domain/models/audit_entry.dart';
import '../../domain/models/consent.dart';
import '../../domain/models/evento_clinico.dart';
import '../../domain/models/patient.dart';
import '../../domain/models/protocolo.dart';

/// Lo que viaja al servidor, y con qué forma exacta.
///
/// Las claves de aquí son el contrato con `api/sivap/modelos.py`. Si una deja
/// de coincidir, el servidor rechaza el lote entero con un 422 — a propósito:
/// un envío que ni se puede leer no es un dato de campo discutible, es la app
/// enviando algo que no debería existir, y conviene verlo de golpe.
///
/// Nada de esto lleva identidad fuera de `identidad`, que va aparte dentro del
/// paciente (CLAUDE.md §1): así el servidor puede guardar el dataset clínico
/// sin ella.
class Lote {
  Lote({
    required this.dispositivoId,
    this.pacientes = const [],
    this.consentimientos = const [],
    this.eventos = const [],
    this.auditoria = const [],
    String? id,
  }) : id = id ?? Ids.nuevo();

  /// Lo genera el dispositivo, y es lo que hace el envío repetible.
  ///
  /// Si la conexión se corta después de que el servidor guarde pero antes de
  /// que llegue la respuesta —que con esta conectividad va a pasar—, el mismo
  /// lote reenviado devuelve el resultado guardado sin duplicar nada.
  final String id;
  final String dispositivoId;

  final List<PacienteEnviable> pacientes;
  final List<ConsentimientoEnviable> consentimientos;
  final List<EventoEnviable> eventos;
  final List<AuditoriaEnviable> auditoria;

  bool get vacio =>
      pacientes.isEmpty &&
      consentimientos.isEmpty &&
      eventos.isEmpty &&
      auditoria.isEmpty;

  int get registros =>
      pacientes.length +
      consentimientos.length +
      auditoria.length +
      eventos.length +
      eventos.fold(0, (n, e) => n + e.valores.length);

  Map<String, Object?> aJson() => {
        'id': id,
        'dispositivo_id': dispositivoId,
        'pacientes': [for (final p in pacientes) p.aJson()],
        'consentimientos': [for (final c in consentimientos) c.aJson()],
        'eventos': [for (final e in eventos) e.aJson()],
        'auditoria': [for (final a in auditoria) a.aJson()],
      };
}

class PacienteEnviable {
  const PacienteEnviable(this.paciente);
  final Patient paciente;

  Map<String, Object?> aJson() => {
        'id': paciente.id,
        'codigo': paciente.codigo,
        'institucion_codigo': paciente.institucion.codigo,
        'edad': paciente.edad,
        'sexo': paciente.sexo.name,
        'enrolado_en': paciente.enroladoEn.toUtc().toIso8601String(),
        'identidad': {
          'nombre': paciente.nombre,
          'numero_historia_clinica': paciente.numeroHistoriaClinica,
          'telefono_principal': paciente.telefonoPrincipal,
          'telefono_secundario': paciente.telefonoSecundario,
        },
        'asignacion': {
          'secuencia_etiqueta': paciente.secuencia,
          'posicion': paciente.posicionSecuencia,
          'protocolo': paciente.protocolo.name,
          'asignado_en': paciente.asignadoEn.toUtc().toIso8601String(),
        },
      };
}

class ConsentimientoEnviable {
  const ConsentimientoEnviable(this.consentimiento);
  final Consent consentimiento;

  Map<String, Object?> aJson() => {
        'id': consentimiento.id,
        'paciente_id': consentimiento.patientId,
        'version_documento': consentimiento.versionDocumento,
        'codigo_cei': consentimiento.codigoCei,
        'firmado_en': consentimiento.firmadoEn.toUtc().toIso8601String(),
        'testigo_id': consentimiento.testigoId,
        // Trazos normalizados 0..1: independientes del tamaño de la pantalla
        // que los capturó, así que se pueden volver a dibujar en cualquiera.
        'firma': {
          'trazos': [
            for (final trazo in consentimiento.firmaTrazos)
              [
                for (final punto in trazo) {'x': punto.x, 'y': punto.y},
              ],
          ],
        },
      };
}

class EventoEnviable {
  const EventoEnviable(this.evento, this.tipos);

  final EventoClinico evento;

  /// Tipo de dato de cada campo, para que el servidor no tenga que adivinarlo.
  final Map<String, String> tipos;

  List<MapEntry<String, Object?>> get valores => evento.valores.entries.toList();

  Map<String, Object?> aJson() => {
        'id': evento.id,
        'paciente_id': evento.patientId,
        'tipo': _nombreServidor(evento.tipo),
        'ocurrencia': evento.ocurrencia,
        'fecha_ocurrencia': _soloFecha(evento.fechaOcurrencia),
        'institucion_codigo': evento.institucion.codigo,
        'fecha_captura':
            (evento.fechaCaptura ?? evento.fechaOcurrencia).toUtc()
                .toIso8601String(),
        'valores': [
          for (final entrada in evento.valores.entries)
            {
              'campo': entrada.key,
              'tipo': tipos[entrada.key] ?? 'texto',
              'valor': _comoTexto(entrada.value),
            },
        ],
      };
}

class AuditoriaEnviable {
  const AuditoriaEnviable(this.entrada);
  final AuditEntry entrada;

  Map<String, Object?> aJson() => {
        'id': entrada.id,
        'ocurrido_en': entrada.ocurridoEn.toUtc().toIso8601String(),
        'entidad': entrada.entidad.name,
        'entidad_id': entrada.entidadId,
        'descripcion_objetivo': entrada.descripcionObjetivo,
        'campo': entrada.campo,
        'valor_anterior': entrada.valorAnterior,
        'valor_nuevo': entrada.valorNuevo,
        'motivo': entrada.motivo,
      };
}

/// `TipoEvento.pruebaVentilacionEspontanea` → `prueba_ventilacion_espontanea`.
///
/// Dart nombra en camello y PostgreSQL en snake. La conversión va aquí, en un
/// sitio, y no repartida por cada llamada.
String _nombreServidor(TipoEvento tipo) => tipo.name
    .replaceAllMapped(RegExp('[A-Z]'), (m) => '_${m[0]!.toLowerCase()}');

String _soloFecha(DateTime fecha) =>
    '${fecha.year.toString().padLeft(4, '0')}-'
    '${fecha.month.toString().padLeft(2, '0')}-'
    '${fecha.day.toString().padLeft(2, '0')}';

/// Los valores viajan como texto porque así los guarda el servidor: una sola
/// columna para todos los tipos, con el tipo declarado al lado. El dataset se
/// convierte al exportar, donde sí se sabe qué es cada cosa.
String? _comoTexto(Object? valor) => switch (valor) {
      null => null,
      bool b => b ? 'true' : 'false',
      List l => l.join(' · '),
      DateTime d => _soloFecha(d),
      _ => valor.toString(),
    };

// ── Lo que responde el servidor ───────────────────────────────────

class Sesion {
  const Sesion({
    required this.token,
    required this.expiraEn,
    required this.investigadorId,
    required this.usuario,
    required this.nombre,
    required this.institucion,
    required this.roles,
  });

  factory Sesion.desdeJson(Map<String, dynamic> json) {
    final quien = json['investigador'] as Map<String, dynamic>;
    return Sesion(
      token: json['token'] as String,
      expiraEn: DateTime.parse(json['expira_en'] as String),
      investigadorId: quien['id'] as String,
      usuario: quien['usuario'] as String,
      nombre: quien['nombre'] as String,
      institucion: quien['institucion'] as String,
      roles: [for (final r in quien['roles'] as List) r as String],
    );
  }

  final String token;
  final DateTime expiraEn;
  final String investigadorId;
  final String usuario;
  final String nombre;
  final String institucion;
  final List<String> roles;
}

/// El tramo de la secuencia que le tocó a este dispositivo.
///
/// `codigoBinario` trae **solo los bits de este tramo**. El dispositivo nunca
/// recibe la secuencia completa del estudio: si se pierde el teléfono, lo que
/// se compromete es su tramo, no el ensayo entero.
class Tramo {
  const Tramo({
    required this.desde,
    required this.hasta,
    required this.consumidas,
    required this.codigoBinario,
    required this.asignadoEn,
  });

  factory Tramo.desdeJson(Map<String, dynamic> json) => Tramo(
        desde: json['desde'] as int,
        hasta: json['hasta'] as int,
        consumidas: json['consumidas'] as int,
        codigoBinario: json['codigo_binario'] as String,
        asignadoEn: DateTime.parse(json['asignado_en'] as String),
      );

  final int desde;

  /// Exclusivo: el tramo cubre `desde` .. `hasta - 1`.
  final int hasta;

  final int consumidas;
  final String codigoBinario;
  final DateTime asignadoEn;

  int get total => hasta - desde;
  int get libres => total - consumidas;

  /// La siguiente posición sin consumir, o `null` si el tramo se agotó.
  ///
  /// Cuando devuelve `null` y no hay conexión para pedir otro tramo, **hay que
  /// dejar de enrolar**. Improvisar una asignación es exactamente lo que la
  /// aleatorización pre-generada existe para evitar.
  int? get siguientePosicion =>
      libres > 0 ? desde + consumidas : null;

  Protocolo? protocoloEn(int posicion) {
    final indice = posicion - desde;
    if (indice < 0 || indice >= codigoBinario.length) return null;
    return codigoBinario[indice] == '1' ? Protocolo.b : Protocolo.a;
  }
}

class ResultadoLote {
  const ResultadoLote({
    required this.loteId,
    required this.registros,
    required this.aceptados,
    required this.rechazados,
    required this.detalle,
    required this.yaRecibido,
  });

  factory ResultadoLote.desdeJson(Map<String, dynamic> json) => ResultadoLote(
        loteId: json['lote_id'] as String,
        registros: json['registros'] as int,
        aceptados: json['aceptados'] as int,
        rechazados: json['rechazados'] as int,
        detalle: [
          for (final r in json['detalle'] as List)
            Rechazo(
              tipo: r['tipo'] as String,
              id: r['id'] as String,
              motivo: r['motivo'] as String,
            ),
        ],
        yaRecibido: json['ya_recibido'] as bool? ?? false,
      );

  final String loteId;
  final int registros;
  final int aceptados;
  final int rechazados;
  final List<Rechazo> detalle;

  /// El lote ya se había procesado antes y el servidor devolvió lo guardado.
  final bool yaRecibido;

  bool get todoEntro => rechazados == 0;

  /// Los identificadores que el servidor no admitió, para no darlos por
  /// enviados. Lo demás sí entró, aunque el lote llevara rechazos.
  Set<String> get idsRechazados => {
        for (final r in detalle) r.id.split('/').first,
      };
}

class Rechazo {
  const Rechazo({required this.tipo, required this.id, required this.motivo});

  /// `paciente`, `consentimiento`, `evento`, `valor` o `auditoria`.
  final String tipo;
  final String id;
  final String motivo;

  @override
  String toString() => '$tipo $id: $motivo';
}
