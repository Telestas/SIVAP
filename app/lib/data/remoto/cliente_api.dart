import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'lote.dart';
import 'cliente_remoto.dart';

/// Lo que la app le dice al servidor central.
///
/// **La captura no depende de esto** (CLAUDE.md §12). La app abre, enrola y
/// registra eventos sin haber hablado nunca con el servidor; esta clase solo
/// sirve para consolidar después. Si todo lo de aquí falla, el trabajo del
/// turno sigue guardado en el teléfono.
///
/// Por eso los errores se separan en dos, y la diferencia manda:
///
///  - [SinConexion] — no se llegó al servidor. Se reintenta más tarde y no se
///    toca nada de lo que hay guardado.
///  - [ErrorDelServidor] — se llegó y dijo que no. Reintentar sin más
///    repetiría el mismo error: alguien tiene que mirarlo.
///
/// Confundirlas es lo que produce colas que se reintentan para siempre.
class ClienteApi implements ClienteRemoto {
  ClienteApi({required this.base, http.Client? cliente, this.tiempoLimite})
      : _http = cliente ?? http.Client();

  /// Raíz del servicio, sin la barra final: `https://servidor/api`.
  final Uri base;

  final http.Client _http;

  /// Cuánto se espera antes de dar la conexión por perdida.
  ///
  /// Generoso a propósito: una conexión lenta que acaba llegando es preferible
  /// a un reintento que vuelve a empezar de cero.
  final Duration? tiempoLimite;

  String? _token;

  @override
  bool get haySesion => _token != null;

  @override
  void olvidarSesion() => _token = null;

  @override
  void cerrar() => _http.close();

  // ── Sesión ──────────────────────────────────────────────────────

  /// Abre sesión y guarda el token para el resto de las llamadas.
  ///
  /// Esto **no** es el acceso a la app: la app se abre sin conexión. El token
  /// solo hace falta para hablar con el servidor.
  Future<Sesion> abrirSesion({
    required String usuario,
    required String contrasena,
    String? dispositivoId,
  }) async {
    final cuerpo = await _pedir('POST', 'sesion', autenticado: false, json: {
      'usuario': usuario,
      'contrasena': contrasena,
      if (dispositivoId != null) 'dispositivo_id': dispositivoId,
    });
    _token = cuerpo['token'] as String;
    return Sesion.desdeJson(cuerpo);
  }

  Future<void> cerrarSesion() async {
    if (_token == null) return;
    await _pedir('DELETE', 'sesion');
    _token = null;
  }

  // ── Configuración del estudio ───────────────────────────────────

  /// Lo que el dispositivo descarga y guarda para trabajar sin conexión: los
  /// centros, si tienen aprobación del CEI, y la definición de formularios.
  ///
  /// Lo que **no** viaja aquí es la secuencia de aleatorización. Se entrega por
  /// tramos, y cada dispositivo solo ve el suyo.
  Future<Map<String, dynamic>> configuracionEstudio() =>
      _pedir('GET', 'estudio');

  // ── Dispositivo ─────────────────────────────────────────────────

  /// Registra este aparato, o actualiza su etiqueta si ya estaba.
  ///
  /// El identificador lo trae el dispositivo porque tiene que poder generarse
  /// sin conexión, igual que los de pacientes y eventos.
  Future<Map<String, dynamic>> registrarDispositivo({
    required String id,
    required String etiqueta,
  }) =>
      _pedir('POST', 'dispositivos', json: {'id': id, 'etiqueta': etiqueta});

  /// Pide el tramo de la secuencia que le toca a este dispositivo.
  ///
  /// Devuelve el tramo en curso mientras le queden posiciones, y solo entrega
  /// uno nuevo cuando el anterior se agotó.
  Future<Tramo> pedirTramo(String dispositivoId) async =>
      Tramo.desdeJson(await _pedir('POST', 'dispositivos/$dispositivoId/tramo'));

  // ── Sincronización ──────────────────────────────────────────────

  /// Envía un lote y devuelve qué entró y qué no.
  ///
  /// Reenviar el mismo lote es seguro: el servidor lo reconoce por su
  /// identificador y devuelve el resultado que ya había guardado. Eso es lo que
  /// hace recuperable el caso que va a ocurrir de verdad — que el servidor
  /// guarde y la respuesta no llegue.
  @override
  Future<ResultadoLote> enviar(Lote lote) async {
    final cuerpo = await _pedir('POST', 'sincronizacion', json: lote.aJson());
    try {
      return ResultadoLote.desdeJson(cuerpo);
    } on Object {
      // Una respuesta con la forma que no es —un proxy que devuelve su propia
      // página, una versión del servidor que no cuadra— no debe reventar la
      // app con un error de tipo. Es un error del servidor como cualquier
      // otro, y lo importante es que no se dé nada por enviado.
      throw const ErrorDelServidor(
          200, 'El servidor respondió algo que no se puede interpretar.');
    }
  }

  // ── Fontanería ──────────────────────────────────────────────────

  Future<Map<String, dynamic>> _pedir(
    String metodo,
    String ruta, {
    Map<String, Object?>? json,
    bool autenticado = true,
  }) async {
    if (autenticado && _token == null) {
      throw const SesionCaducada('No hay sesión abierta con el servidor.');
    }

    final peticion = http.Request(metodo, _url(ruta))
      ..headers.addAll({
        'Content-Type': 'application/json; charset=utf-8',
        if (autenticado) 'Authorization': 'Bearer $_token',
      });
    if (json != null) peticion.body = jsonEncode(json);

    late final http.StreamedResponse respuesta;
    try {
      final envio = _http.send(peticion);
      respuesta = await (tiempoLimite == null
          ? envio
          : envio.timeout(tiempoLimite!));
    } on TimeoutException {
      throw const SinConexion('El servidor tardó demasiado en responder.');
    } on Exception catch (error) {
      // Sin red, DNS que no resuelve, TLS que no valida: desde aquí es lo
      // mismo, y todas se reintentan igual.
      throw SinConexion(error.toString());
    }

    final texto = await respuesta.stream.bytesToString();

    if (respuesta.statusCode == 401) {
      _token = null;
      throw SesionCaducada(_detalle(texto) ?? 'La sesión ya no vale.');
    }
    if (respuesta.statusCode == 204 || texto.isEmpty) return const {};
    if (respuesta.statusCode >= 400) {
      throw ErrorDelServidor(respuesta.statusCode,
          _detalle(texto) ?? 'El servidor respondió ${respuesta.statusCode}.');
    }

    final decodificado = jsonDecode(texto);
    if (decodificado is! Map<String, dynamic>) {
      throw ErrorDelServidor(
          respuesta.statusCode, 'Respuesta con una forma inesperada.');
    }
    return decodificado;
  }

  /// `https://servidor/api` + `sesion` → `https://servidor/api/sesion`.
  Uri _url(String ruta) {
    final raiz = base.path.endsWith('/')
        ? base.path.substring(0, base.path.length - 1)
        : base.path;
    return base.replace(path: '$raiz/$ruta');
  }

  /// FastAPI pone el motivo en `detail`, y a veces es una lista de errores de
  /// validación. Interesa que llegue legible a quien lo lea en el teléfono.
  static String? _detalle(String texto) {
    if (texto.isEmpty) return null;
    try {
      final cuerpo = jsonDecode(texto);
      if (cuerpo is! Map) return null;
      final detalle = cuerpo['detail'];
      if (detalle is String) return detalle;
      if (detalle is List) {
        return detalle
            .map((e) => e is Map ? (e['msg'] ?? e).toString() : e.toString())
            .join(' · ');
      }
    } on FormatException {
      return null;
    }
    return null;
  }
}

/// No se llegó al servidor. Se reintenta.
class SinConexion implements Exception {
  const SinConexion(this.detalle);
  final String detalle;

  @override
  String toString() => 'Sin conexión con el servidor.';
}

/// Se llegó, y dijo que no. Reintentar repetiría el error.
class ErrorDelServidor implements Exception {
  const ErrorDelServidor(this.codigo, this.detalle);
  final int codigo;
  final String detalle;

  @override
  String toString() => detalle;
}

/// El token no vale: caducó, se revocó, o la cuenta se dio de baja.
///
/// Se distingue del resto porque tiene arreglo desde la app —volver a abrir
/// sesión— y no debería contarse como error del lote.
class SesionCaducada implements Exception {
  const SesionCaducada(this.detalle);
  final String detalle;

  @override
  String toString() => detalle;
}
