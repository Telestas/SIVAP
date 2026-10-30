import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import '../local/db/database_key.dart';
import '../../domain/models/institucion.dart';
import '../../domain/models/role.dart';
import 'cliente_http_stub.dart' if (dart.library.io) 'cliente_http_io.dart';
import 'diagnostico_red_stub.dart'
    if (dart.library.io) 'diagnostico_red_io.dart';

/// Transporte móvil por el mismo origen de Cloudflare que usa la web.
/// Las reglas de Firestore siguen verificando el ID token de Firebase.
class FirebaseRestMovil {
  FirebaseRestMovil({http.Client? cliente, AlmacenSesion? almacen})
      : _cliente = cliente ?? crearClienteHttp(),
        _almacen = almacen ?? const AlmacenSesionSeguro();

  static const origen = 'https://sivap.pages.dev';
  static const proyecto = 'sivap-f5060';
  static const clavePublica = 'AIzaSyDDk4UqDn-wYhAjSnI4WR4N3K79NjhA8Tg';
  static const _documentos =
      '/v1/projects/$proyecto/databases/(default)/documents';
  static const _claveSesion = 'sivap.firebase.refresh.v1';
  static const _clavePerfil = 'sivap.firebase.perfil.v1';

  final http.Client _cliente;
  final AlmacenSesion _almacen;
  String? _idToken;
  String? _refreshToken;
  String? _uid;
  DateTime? _expira;
  Future<void>? _renovacion;

  String? get uid => _uid;
  bool get haySesion => _refreshToken != null;

  Future<Map<String, dynamic>> _peticion(
      String ruta, Map<String, Object?> datos,
      {bool autenticada = false, bool formulario = false}) async {
    final token = autenticada ? await idToken() : null;
    final respuesta = await _enviar('POST', ruta, datos,
        token: token, formulario: formulario);
    return _decodificar(respuesta);
  }

  Future<http.Response> _enviar(String metodo, String ruta, Object? datos,
      {String? token, bool formulario = false}) async {
    final cabeceras = <String, String>{
      'Content-Type':
          formulario ? 'application/x-www-form-urlencoded' : 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
    try {
      final solicitud = http.Request(metodo, Uri.parse('$origen$ruta'))
        ..headers.addAll(cabeceras);
      if (datos != null) {
        solicitud.body = formulario
            ? Uri(
                queryParameters: (datos as Map<String, Object?>).map(
                    (clave, valor) => MapEntry(clave, valor.toString()))).query
            : jsonEncode(datos);
      }
      final flujo =
          await _cliente.send(solicitud).timeout(const Duration(seconds: 30));
      return await http.Response.fromStream(flujo)
          .timeout(const Duration(seconds: 30));
    } on TimeoutException {
      throw const FirebaseRestError(
          0, 'La conexión a sivap.pages.dev tardó más de 30 segundos.');
    } on Object catch (error) {
      final mensaje = diagnosticoConexion(error);
      if (mensaje == null) rethrow;
      throw FirebaseRestError(0, mensaje);
    }
  }

  Map<String, dynamic> _decodificar(http.Response respuesta) {
    final tipo = respuesta.headers['content-type']?.toLowerCase() ?? '';
    if (!tipo.contains('json')) {
      throw FirebaseRestError(respuesta.statusCode,
          'SIVAP no recibió una respuesta válida (HTTP ${respuesta.statusCode}).');
    }
    final Object? cuerpo;
    try {
      cuerpo = jsonDecode(respuesta.body);
    } on FormatException {
      throw FirebaseRestError(respuesta.statusCode,
          'SIVAP recibió una respuesta dañada (HTTP ${respuesta.statusCode}).');
    }
    if (cuerpo is! Map<String, dynamic>) {
      throw FirebaseRestError(
          respuesta.statusCode, 'SIVAP recibió una respuesta inesperada.');
    }
    if (respuesta.statusCode >= 400) {
      final error = cuerpo['error'];
      final codigo = error is Map
          ? (error['status'] ?? error['message'])?.toString()
          : null;
      throw FirebaseRestError(
          respuesta.statusCode, _mensajeError(codigo, respuesta.statusCode),
          codigo: codigo);
    }
    return cuerpo;
  }

  static String _mensajeError(String? codigo, int estado) => switch (codigo) {
        'INVALID_LOGIN_CREDENTIALS' ||
        'EMAIL_NOT_FOUND' ||
        'INVALID_PASSWORD' =>
          'Correo o contraseña incorrectos.',
        'EMAIL_EXISTS' => 'El correo ya tiene una cuenta.',
        'WEAK_PASSWORD' => 'La contraseña debe tener al menos seis caracteres.',
        'INVALID_EMAIL' => 'El correo no tiene un formato válido.',
        'TOO_MANY_ATTEMPTS_TRY_LATER' =>
          'Demasiados intentos. Intente más tarde.',
        'ABORTED' =>
          'La operación coincidió con otro cambio. Intente de nuevo.',
        'TOKEN_EXPIRED' ||
        'INVALID_REFRESH_TOKEN' ||
        'USER_DISABLED' =>
          'La sesión caducó. Vuelva a entrar.',
        _ => estado == 403
            ? 'Firebase rechazó esta operación. Compruebe su rol y centro.'
            : 'No se pudo completar la operación (HTTP $estado).',
      };

  Future<void> entrar(String correo, String contrasena) async {
    final datos = await _peticion(
      '/api/firebase/auth/v1/accounts:signInWithPassword?key=$clavePublica',
      {
        'email': correo.trim(),
        'password': contrasena,
        'returnSecureToken': true
      },
    );
    await _guardarSesion(datos);
  }

  Future<void> crearCuenta(String correo, String contrasena) async {
    final datos = await _peticion(
        '/api/firebase/auth/v1/accounts:signUp?key=$clavePublica', {
      'email': correo.trim(),
      'password': contrasena,
      'returnSecureToken': true
    });
    await _guardarSesion(datos);
    await salir();
  }

  Future<void> _guardarSesion(Map<String, dynamic> datos) async {
    _idToken = datos['idToken'] as String;
    _refreshToken = datos['refreshToken'] as String;
    _uid = datos['localId'] as String;
    _expira = DateTime.now().add(
      Duration(seconds: int.tryParse(datos['expiresIn'].toString()) ?? 3600),
    );
    await _almacen.escribir(_claveSesion, _refreshToken!);
  }

  Future<String> idToken() async {
    if (_idToken != null &&
        _expira != null &&
        DateTime.now()
            .isBefore(_expira!.subtract(const Duration(minutes: 5)))) {
      return _idToken!;
    }
    _refreshToken ??= await _almacen.leer(_claveSesion);
    if (_refreshToken == null) {
      throw const FirebaseRestError(401, 'Abra sesión para continuar.');
    }
    _renovacion ??= _renovar();
    try {
      await _renovacion;
    } finally {
      _renovacion = null;
    }
    return _idToken!;
  }

  Future<void> _renovar() async {
    final datos = await _peticion(
        '/api/firebase/token/v1/token?key=$clavePublica',
        {'grant_type': 'refresh_token', 'refresh_token': _refreshToken!},
        formulario: true);
    _idToken = datos['id_token'] as String;
    _refreshToken = datos['refresh_token'] as String;
    _uid = datos['user_id'] as String;
    _expira = DateTime.now().add(Duration(
        seconds: int.tryParse(datos['expires_in'].toString()) ?? 3600));
    await _almacen.escribir(_claveSesion, _refreshToken!);
  }

  Future<void> restaurarToken() async {
    _refreshToken = await _almacen.leer(_claveSesion);
    if (_refreshToken == null) return;
    await idToken();
  }

  Future<Map<String, dynamic>> datosCuenta() async {
    final datos = await _peticion(
        '/api/firebase/auth/v1/accounts:lookup?key=$clavePublica',
        {'idToken': await idToken()});
    final usuarios = datos['users'] as List<dynamic>?;
    if (usuarios == null || usuarios.isEmpty) {
      throw const FirebaseRestError(401, 'La cuenta ya no está disponible.');
    }
    final usuario = Map<String, dynamic>.from(usuarios.first as Map);
    return usuario;
  }

  Future<void> enviarCorreoVerificacion() async {
    await _peticion(
        '/api/firebase/auth/v1/accounts:sendOobCode?key=$clavePublica',
        {'requestType': 'VERIFY_EMAIL', 'idToken': await idToken()});
  }

  Future<void> recuperarAcceso(String correo) async {
    try {
      await _peticion(
          '/api/firebase/auth/v1/accounts:sendOobCode?key=$clavePublica',
          {'requestType': 'PASSWORD_RESET', 'email': correo.trim()});
    } on FirebaseRestError catch (error) {
      if (error.codigo != 'EMAIL_NOT_FOUND') rethrow;
    }
  }

  Future<Map<String, dynamic>?> leer(String ruta) async {
    final respuesta = await _enviar('GET', '$_documentos/$ruta', null,
        token: await idToken());
    if (respuesta.statusCode == 404 &&
        respuesta.headers['content-type']?.contains('json') == true) {
      final error = jsonDecode(respuesta.body) as Map<String, dynamic>;
      if ((error['error'] as Map?)?['status'] == 'NOT_FOUND') return null;
    }
    return valoresDocumento(_decodificar(respuesta));
  }

  /// Consulta solo solicitudes del centro; el filtro forma parte de la
  /// petición porque las reglas rechazan consultas de todos los centros.
  Future<List<SolicitudRest>> consultarSolicitudes(String codigoCentro) async {
    final respuesta = await _enviar(
        'POST',
        '$_documentos:runQuery',
        {
          'structuredQuery': {
            'from': [
              {'collectionId': 'solicitudes_acceso'}
            ],
            'where': {
              'fieldFilter': {
                'field': {'fieldPath': 'institucion_codigo'},
                'op': 'EQUAL',
                'value': {'stringValue': codigoCentro},
              },
            },
          },
        },
        token: await idToken());
    if (respuesta.statusCode >= 400) _decodificar(respuesta);
    final salida = <SolicitudRest>[];
    for (final resultado in decodificarFlujo(respuesta.body)) {
      final documento = resultado['document'];
      if (documento is! Map) continue;
      final nombre = documento['name'] as String;
      salida.add(SolicitudRest(
        nombre.substring(nombre.lastIndexOf('/') + 1),
        valoresDocumento(Map<String, dynamic>.from(documento)),
      ));
    }
    return salida;
  }

  /// Aprueba solicitud y perfil en un único commit con la hora del servidor.
  Future<void> aprobarSolicitud(SolicitudRest solicitud, String rol,
      String codigoCentro, String aprobador) async {
    final datos = solicitud.datos;
    if (datos['institucion_codigo'] != codigoCentro ||
        datos['estado'] != 'pendiente' ||
        rol == 'investigadorPrincipal') {
      throw StateError('La solicitud o la función no son aprobables.');
    }
    await commit([
      escritura(
          'investigadores/${solicitud.uid}',
          {
            'nombre': datos['nombre'],
            'correo': datos['correo'],
            'institucion_codigo': codigoCentro,
            'roles': [rol],
            'aprobado_por': aprobador,
          },
          crear: true,
          tiempos: const ['aprobado_en']),
      escritura('solicitudes_acceso/${solicitud.uid}', {
        'estado': 'aprobado',
        'rol_aprobado': rol,
        'aprobado_por': aprobador,
      }, camposActualizar: const [
        'estado',
        'rol_aprobado',
        'aprobado_por'
      ], tiempos: const [
        'aprobado_en'
      ]),
    ]);
  }

  Future<void> escribir(String ruta, Map<String, Object?> datos,
      {bool crear = false,
      bool marcaTiempo = false,
      bool fusionar = false}) async {
    final tiempos = marcaTiempo
        ? datos.keys
            .where(
                (clave) => clave == 'solicitado_en' || clave == 'registrado_en')
            .toList()
        : <String>[];
    await commit([
      escritura(ruta, datos,
          crear: crear,
          tiempos: tiempos,
          camposActualizar: fusionar
              ? datos.keys.where((clave) => !tiempos.contains(clave)).toList()
              : null),
    ]);
  }

  Future<String> comenzarTransaccion() async {
    final datos = await _peticion(
        '$_documentos:beginTransaction',
        {
          'options': {'readWrite': {}}
        },
        autenticada: true);
    return datos['transaction'] as String;
  }

  Future<Map<String, Map<String, dynamic>?>> leerTransaccion(
      String transaccion, List<String> rutas) async {
    final nombres = [
      for (final ruta in rutas)
        'projects/$proyecto/databases/(default)/documents/$ruta'
    ];
    final respuesta = await _enviar('POST', '$_documentos:batchGet',
        {'documents': nombres, 'transaction': transaccion},
        token: await idToken());
    if (respuesta.statusCode >= 400) {
      _decodificar(respuesta);
    }
    final salida = <String, Map<String, dynamic>?>{};
    for (final dato in decodificarFlujo(respuesta.body)) {
      final nombre = (dato['found'] as Map?)?['name'] ?? dato['missing'];
      if (nombre is! String) continue;
      salida[nombre] = dato['found'] is Map
          ? valoresDocumento(Map<String, dynamic>.from(dato['found'] as Map))
          : null;
    }
    return salida;
  }

  /// Google REST devuelve un arreglo JSON; algunos transportes transmiten
  /// cada respuesta del flujo como un objeto JSON por línea.
  static List<Map<String, dynamic>> decodificarFlujo(String cuerpo) {
    try {
      final dato = jsonDecode(cuerpo);
      if (dato is List) {
        return [
          for (final elemento in dato)
            Map<String, dynamic>.from(elemento as Map)
        ];
      }
      if (dato is Map) return [Map<String, dynamic>.from(dato)];
    } on FormatException {
      try {
        return [
          for (final linea in const LineSplitter().convert(cuerpo))
            if (linea.trim().isNotEmpty)
              Map<String, dynamic>.from(jsonDecode(linea) as Map),
        ];
      } on FormatException {
        // Se traduce abajo a un error sin exponer datos clínicos de la respuesta.
      }
    }
    throw const FirebaseRestError(
        502, 'Firestore devolvió una respuesta inválida.');
  }

  Future<void> commit(List<Map<String, Object?>> escrituras,
      {String? transaccion}) async {
    await _peticion(
        '$_documentos:commit',
        {
          'writes': escrituras,
          if (transaccion != null) 'transaction': transaccion,
        },
        autenticada: true);
  }

  /// Repite una transacción completa cuando Firestore detecta contención.
  Future<T> reintentarTransaccion<T>(Future<T> Function() operacion) async {
    for (var intento = 0;; intento++) {
      try {
        return await operacion();
      } on FirebaseRestError catch (error) {
        if (error.codigo != 'ABORTED' || intento >= 2) rethrow;
        await Future<void>.delayed(Duration(milliseconds: 100 * (intento + 1)));
      }
    }
  }

  static Map<String, Object?> escritura(String ruta, Map<String, Object?> datos,
      {bool crear = false,
      List<String> tiempos = const [],
      List<String>? camposActualizar}) {
    final campos = Map<String, Object?>.from(datos)
      ..removeWhere((clave, _) => tiempos.contains(clave));
    return {
      'update': {
        'name': 'projects/$proyecto/databases/(default)/documents/$ruta',
        'fields': camposDocumento(campos),
      },
      if (crear) 'currentDocument': {'exists': false},
      if (camposActualizar != null)
        'updateMask': {'fieldPaths': camposActualizar},
      if (tiempos.isNotEmpty)
        'updateTransforms': [
          for (final campo in tiempos)
            {'fieldPath': campo, 'setToServerValue': 'REQUEST_TIME'},
        ],
    };
  }

  static Map<String, Object?> camposDocumento(Map<String, Object?> datos) => {
        for (final entrada in datos.entries) entrada.key: _valor(entrada.value),
      };

  static Map<String, Object?> _valor(Object? dato) {
    if (dato == null) return {'nullValue': null};
    if (dato is bool) return {'booleanValue': dato};
    if (dato is int) return {'integerValue': dato.toString()};
    if (dato is num) return {'doubleValue': dato};
    if (dato is String) return {'stringValue': dato};
    if (dato is DateTime) {
      return {'timestampValue': dato.toUtc().toIso8601String()};
    }
    if (dato is Map) {
      return {
        'mapValue': {'fields': camposDocumento(Map<String, Object?>.from(dato))}
      };
    }
    if (dato is List) {
      return {
        'arrayValue': {
          'values': [for (final valor in dato) _valor(valor)]
        }
      };
    }
    throw ArgumentError('Tipo de dato no admitido por Firestore.');
  }

  static Map<String, dynamic> valoresDocumento(Map<String, dynamic> documento) {
    final campos = documento['fields'];
    if (campos is! Map) return {};
    return {
      for (final e in campos.entries)
        e.key.toString(): _desdeValor(e.value as Map)
    };
  }

  static Object? _desdeValor(Map dato) {
    if (dato.containsKey('nullValue')) return null;
    if (dato.containsKey('booleanValue')) return dato['booleanValue'];
    if (dato.containsKey('integerValue')) {
      return int.parse(dato['integerValue'].toString());
    }
    if (dato.containsKey('doubleValue')) {
      return (dato['doubleValue'] as num).toDouble();
    }
    if (dato.containsKey('stringValue')) return dato['stringValue'];
    if (dato.containsKey('timestampValue')) return dato['timestampValue'];
    if (dato.containsKey('mapValue')) {
      return valoresDocumento(
          Map<String, dynamic>.from(dato['mapValue'] as Map));
    }
    if (dato.containsKey('arrayValue')) {
      final valores =
          (dato['arrayValue'] as Map)['values'] as List? ?? const [];
      return [for (final valor in valores) _desdeValor(valor as Map)];
    }
    throw const FormatException('Tipo de Firestore desconocido');
  }

  Future<void> guardarPerfil(Investigador investigador) async {
    await _almacen.escribir(
        _clavePerfil,
        jsonEncode({
          'uid': investigador.id,
          'correo': investigador.usuario,
          'nombre': investigador.nombre,
          'roles': investigador.roles.map((r) => r.name).toList(),
          'institucion_codigo': investigador.institucion.codigo,
          'institucion_nombre': investigador.institucion.nombre,
        }));
  }

  Future<Investigador?> perfilGuardado() async {
    final texto = await _almacen.leer(_clavePerfil);
    if (texto == null) return null;
    final datos = jsonDecode(texto) as Map<String, dynamic>;
    // Una renovación puede fallar antes de devolver el UID; el perfil cifrado
    // solo es utilizable si existe una sesión guardada en el mismo Keystore.
    if (_refreshToken == null) return null;
    _uid ??= datos['uid'] as String?;
    if (datos['uid'] != _uid) return null;
    return Investigador(
      id: _uid!,
      usuario: datos['correo'] as String,
      nombre: datos['nombre'] as String,
      roles: (datos['roles'] as List)
          .map((r) => Rol.values.byName(r as String))
          .toSet(),
      institucion: Institucion(
        codigo: datos['institucion_codigo'] as String,
        nombre: datos['institucion_nombre'] as String,
      ),
    );
  }

  Future<void> salir() async {
    _idToken = null;
    _refreshToken = null;
    _uid = null;
    _expira = null;
    await _almacen.borrar(_claveSesion);
    await _almacen.borrar(_clavePerfil);
  }

  void cerrar() => _cliente.close();
}

class FirebaseRestError implements Exception {
  const FirebaseRestError(this.estado, this.mensaje, {this.codigo});
  final int estado;
  final String mensaje;
  final String? codigo;
  @override
  String toString() => mensaje;
}

class SolicitudRest {
  const SolicitudRest(this.uid, this.datos);
  final String uid;
  final Map<String, dynamic> datos;
}

/// La sesión nunca se guarda en SQLite ni en archivos accesibles a otras apps.
abstract class AlmacenSesion {
  Future<String?> leer(String clave);
  Future<void> escribir(String clave, String valor);
  Future<void> borrar(String clave);
}

class AlmacenSesionSeguro implements AlmacenSesion {
  const AlmacenSesionSeguro();
  FlutterSecureStorage get _seguro => DatabaseKey.almacenPorDefecto;

  @override
  Future<String?> leer(String clave) => _seguro.read(key: clave);

  @override
  Future<void> escribir(String clave, String valor) =>
      _seguro.write(key: clave, value: valor);

  @override
  Future<void> borrar(String clave) => _seguro.delete(key: clave);
}
