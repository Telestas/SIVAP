import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:http/http.dart' as http;

import '../../core/ids.dart';
import '../../domain/models/role.dart';
import '../../domain/repositories/study_repository.dart';
import 'cliente_api.dart';
import 'cliente_firebase.dart';
import 'cliente_firebase_rest.dart';
import 'cliente_tramos_firestore.dart';
import 'cliente_tramos_rest.dart';
import 'cliente_remoto.dart';
import 'autenticacion_firebase.dart';
import 'autenticacion_rest_movil.dart';
import 'firebase_rest_movil.dart';
import 'cola_de_envio.dart';
import 'lote.dart';

/// Una página HTML de Firebase o de la red nunca es un tramo de aleatorización.
String? mensajeRespuestaTramo(http.Response respuesta) {
  if (respuesta.statusCode == 404) {
    return 'El servicio de tramos aún no está publicado. '
        'El enrolamiento permanece bloqueado.';
  }
  final tipo = respuesta.headers['content-type']?.toLowerCase() ?? '';
  if (!tipo.contains('json')) {
    return 'El servicio de tramos no está disponible '
        '(HTTP ${respuesta.statusCode}). El enrolamiento permanece bloqueado.';
  }
  return null;
}

/// La sincronización, vista desde la app.
///
/// Junta las tres cosas que hasta ahora estaban sueltas: a qué servidor se
/// habla, con qué identidad, y la cola de lo que falta por enviar.
///
/// **Nada de esto condiciona la captura** (CLAUDE.md §12). Sin servidor
/// configurado, sin sesión o sin cobertura, la app enrola y registra igual; lo
/// único que no ocurre es el envío. Por eso no hay reintentos automáticos en
/// bucle ni nada que pueda dejar la interfaz esperando: sincronizar es una
/// acción que alguien decide, y que dice en qué quedó.
class Sincronizacion extends ChangeNotifier {
  Sincronizacion(this._repo,
      {ClienteApi Function(Uri)? construirCliente,
      this.restMovil,
      this.soloLocal = false})
      : _construirCliente =
            construirCliente ?? ((base) => ClienteApi(base: base)) {
    _cargar();
  }

  static const claveServidor = 'servidor_url';
  static const claveDispositivo = 'dispositivo_id';
  static const claveEtiqueta = 'dispositivo_etiqueta';

  final StudyRepository _repo;
  final ClienteApi Function(Uri) _construirCliente;
  final bool soloLocal;
  final FirebaseRestMovil? restMovil;

  ClienteApi? _api;
  ClienteFirebase? _firebase;
  ClienteFirebaseRest? _firebaseRest;
  Uri? _servidor;
  late String _dispositivoId;

  bool _enCurso = false;
  EnvioRealizado? _ultimo;
  Sesion? _sesion;

  Uri? get servidor => _servidor;
  String get dispositivoId => _dispositivoId;
  bool get enCurso => _enCurso;
  bool get configurado => !soloLocal && (usaFirebase || _servidor != null);
  bool get usaFirebase =>
      !soloLocal && (restMovil != null || Firebase.apps.isNotEmpty);
  bool get haySesion => _clienteActivo?.haySesion ?? false;
  Sesion? get sesion => _sesion;

  ClienteRemoto? get _clienteActivo =>
      usaFirebase ? (restMovil != null ? _firebaseRest : _firebase) : _api;

  /// La sesión principal del móvil ya autenticó este perfil. No se solicitan
  /// credenciales por segunda vez para enviar datos.
  void vincularFirebase(Investigador investigador) {
    if (!usaFirebase) return;
    if (restMovil case final rest?) {
      _firebaseRest = ClienteFirebaseRest(
        rest: rest,
        investigadorId: investigador.id,
        institucionCodigo: investigador.institucion.codigo,
        roles: investigador.roles,
      );
    } else {
      _firebase = ClienteFirebase(
        investigadorId: investigador.id,
        institucionCodigo: investigador.institucion.codigo,
        roles: investigador.roles,
      );
    }
    _sesion = Sesion(
      token: 'firebase',
      expiraEn: DateTime.now().toUtc().add(const Duration(hours: 1)),
      investigadorId: investigador.id,
      usuario: investigador.usuario,
      nombre: investigador.nombre,
      institucion: investigador.institucion.codigo,
      roles: investigador.roles.map((r) => r.name).toList(),
    );
    notifyListeners();
  }

  /// Solicita un tramo exclusivo de una reserva administrativa. Si el
  /// aparato no tiene red, su tramo local sigue disponible; si se agotó, el
  /// repositorio impide enrolar.
  Future<String?> solicitarTramo() async {
    if (soloLocal) return 'La demostración no usa tramos reales.';
    final repo = _repo;
    if (!repo.requiereTramos) return 'La demostración no usa tramos reales.';
    if (repo.asignacionesRestantes > 0) return null;
    if (!repo.config.capturaHabilitada) {
      return 'El enrolamiento sigue bloqueado: falta el consentimiento '
          'aprobado del estudio para este centro.';
    }
    if (repo.pendienteDeEnvio().pacientes.isNotEmpty) {
      return 'Sincronice los pacientes pendientes antes de solicitar otro tramo.';
    }
    final rest = restMovil;
    final usuario = rest == null ? FirebaseAuth.instance.currentUser : null;
    final uid = rest?.uid ?? usuario?.uid;
    if (uid == null || _sesion == null) {
      return 'Abra sesión para solicitar un tramo.';
    }
    try {
      final perfil = _sesion!;
      if (!perfil.roles.contains(Rol.reclutador.name) &&
          !perfil.roles.contains(Rol.investigadorPrincipal.name)) {
        return 'Su función no permite enrolar.';
      }
      if (rest != null) {
        await rest.escribir(
            'dispositivos/$_dispositivoId',
            {
              'autor_uid': uid,
              'institucion_codigo': perfil.institucion,
              'etiqueta': repo.ajuste(claveEtiqueta) ?? 'Aparato de campo',
              'registrado_en': null,
            },
            marcaTiempo: true,
            fusionar: true);
      } else {
        final dispositivo = FirebaseFirestore.instance
            .collection('dispositivos')
            .doc(_dispositivoId);
        await dispositivo.set({
          'autor_uid': uid,
          'institucion_codigo': perfil.institucion,
          'etiqueta': repo.ajuste(claveEtiqueta) ?? 'Aparato de campo',
          'registrado_en': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true)).timeout(const Duration(seconds: 30));
      }
      if (repo.ajuste('entrega_tramos') == 'reservas') {
        final datos = await (rest == null
                ? ClienteTramosFirestore().recoger(uid, _dispositivoId)
                : ClienteTramosRest(rest).recoger(uid, _dispositivoId))
            .timeout(const Duration(seconds: 30));
        repo.incorporarTramo(Tramo.desdeJson(datos),
            datos['etiqueta'] as String, _dispositivoId);
        notifyListeners();
        return repo.asignacionesRestantes > 0
            ? null
            : 'El tramo está agotado. La administración debe preparar '
                'la siguiente reserva desde la CLI.';
      }
      if (rest != null) {
        return 'La entrega de tramos no está configurada como reserva. '
            'Consulte a la administración del estudio.';
      }
      final token = await usuario!.getIdToken();
      final proyecto = Firebase.app().options.projectId;
      final respuesta = await http
          .post(
            Uri.parse(
                'https://us-central1-$proyecto.cloudfunctions.net/solicitarTramo'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: jsonEncode({
              'data': {'dispositivo_id': _dispositivoId}
            }),
          )
          .timeout(const Duration(seconds: 30));
      final problema = mensajeRespuestaTramo(respuesta);
      if (problema != null) return problema;
      final Map<String, dynamic> cuerpo;
      try {
        cuerpo = jsonDecode(respuesta.body) as Map<String, dynamic>;
      } on FormatException {
        return 'El servicio de tramos devolvió una respuesta inválida. '
            'No se puede enrolar hasta que esté disponible.';
      } on TypeError {
        return 'El servicio de tramos devolvió una respuesta inválida. '
            'No se puede enrolar hasta que esté disponible.';
      }
      if (respuesta.statusCode != 200 || cuerpo.containsKey('error')) {
        return (cuerpo['error'] as Map?)?['message']?.toString() ??
            'No se pudo reservar un tramo.';
      }
      final datos =
          (cuerpo['result'] ?? cuerpo['response']) as Map<String, dynamic>;
      repo.incorporarTramo(
          Tramo.desdeJson(datos), datos['etiqueta'] as String, _dispositivoId);
      notifyListeners();
      return repo.asignacionesRestantes == 0
          ? 'Sincronice las asignaciones pendientes antes de pedir otro tramo.'
          : null;
    } on Object catch (error) {
      return 'No se pudo solicitar el tramo: $error';
    }
  }

  /// Cómo fue el último envío. Vive en memoria: al reabrir la app se pierde el
  /// detalle, pero no el dato — lo que no entró sigue en la cola y el motivo
  /// vuelve a aparecer en cuanto se reintente.
  EnvioRealizado? get ultimo => _ultimo;

  /// Cuántos registros esperan. Se cuenta sobre el almacén, así que es cierto
  /// aunque nunca se haya hablado con el servidor.
  int get pendientes => _repo.pendienteDeEnvio().registros;

  List<Rechazo> get rechazos => switch (_ultimo) {
        Hecho(:final resultado) => resultado.detalle,
        _ => const [],
      };

  /// El identificador del aparato se crea una vez y se guarda.
  ///
  /// Si se regenerara en cada arranque, el servidor vería un dispositivo nuevo
  /// cada vez y le daría un tramo nuevo de la secuencia de aleatorización,
  /// quemando posiciones que nadie va a usar.
  void _cargar() {
    _dispositivoId = _repo.ajuste(claveDispositivo) ??
        (() {
          final nuevo = Ids.nuevo();
          _repo.guardarAjuste(claveDispositivo, nuevo);
          return nuevo;
        })();

    final url = _repo.ajuste(claveServidor);
    if (url != null && url.isNotEmpty) _apuntarA(Uri.parse(url));
  }

  void _apuntarA(Uri base) {
    _api?.cerrar();
    _servidor = base;
    _api = _construirCliente(base);
    _sesion = null;
  }

  /// Fija a qué servidor habla este aparato. Se guarda para el próximo arranque.
  void configurar(String url) {
    if (soloLocal) return;
    final limpia = url.trim();
    if (limpia.isEmpty) return;
    _repo.guardarAjuste(claveServidor, limpia);
    _apuntarA(Uri.parse(limpia));
    _ultimo = null;
    notifyListeners();
  }

  /// Abre sesión con el servidor.
  ///
  /// No es el acceso a la app: la app se abre sin conexión. Esto solo autoriza
  /// el envío, y el token se queda en memoria — una base que se pueda copiar no
  /// debe llevar dentro con qué entrar.
  Future<String?> entrar(String usuario, String contrasena) async {
    if (soloLocal) return 'Los datos de demostración no se sincronizan.';
    if (usaFirebase) return _entrarFirebase(usuario, contrasena);
    final api = _api;
    if (api == null) return 'Falta configurar la dirección del servidor.';

    _enCurso = true;
    notifyListeners();
    try {
      _sesion = await api.abrirSesion(
        usuario: usuario,
        contrasena: contrasena,
        dispositivoId: _dispositivoId,
      );
      // El servidor tiene que conocer el aparato antes de aceptarle un lote.
      await api.registrarDispositivo(
        id: _dispositivoId,
        etiqueta: _repo.ajuste(claveEtiqueta) ?? 'Aparato de campo',
      );
      return null;
    } on SinConexion {
      return 'Sin conexión con el servidor.';
    } on ErrorDelServidor catch (e) {
      return e.detalle;
    } on SesionCaducada catch (e) {
      return e.detalle;
    } finally {
      _enCurso = false;
      notifyListeners();
    }
  }

  Future<String?> _entrarFirebase(String correo, String contrasena) async {
    _enCurso = true;
    notifyListeners();
    try {
      if (restMovil case final rest?) {
        final investigador =
            await AutenticacionRestMovil(rest).entrar(correo, contrasena);
        vincularFirebase(investigador);
        return null;
      }
      final investigador =
          await AutenticacionFirebase().entrar(correo, contrasena);
      await FirebaseFirestore.instance
          .collection('dispositivos')
          .doc(_dispositivoId)
          .set({
        'autor_uid': investigador.id,
        'institucion_codigo': investigador.institucion.codigo,
        'etiqueta': _repo.ajuste(claveEtiqueta) ?? 'Aparato de campo',
        'registrado_en': FieldValue.serverTimestamp(),
      });
      _sesion = Sesion(
        token: 'firebase',
        expiraEn: DateTime.now().toUtc().add(const Duration(hours: 1)),
        investigadorId: investigador.id,
        usuario: investigador.usuario,
        nombre: investigador.nombre,
        institucion: investigador.institucion.codigo,
        roles: investigador.roles.map((rol) => rol.name).toList(),
      );
      _firebase = ClienteFirebase(
        investigadorId: investigador.id,
        institucionCodigo: investigador.institucion.codigo,
        roles: investigador.roles,
      );
      return null;
    } on AccesoFirebaseRechazado catch (e) {
      return e.mensaje;
    } on PerfilNoAprovisionado catch (e) {
      return e.toString();
    } on FirebaseException catch (e) {
      return e.message ?? 'No se pudo registrar el dispositivo.';
    } finally {
      _enCurso = false;
      notifyListeners();
    }
  }

  void salir() {
    _api?.olvidarSesion();
    _firebase?.olvidarSesion();
    _firebase = null;
    _firebaseRest?.olvidarSesion();
    _firebaseRest = null;
    if (restMovil == null && usaFirebase) {
      unawaited(FirebaseAuth.instance.signOut());
    }
    _sesion = null;
    notifyListeners();
  }

  /// Envía lo pendiente. Devuelve cómo fue, y lo deja anotado para la pantalla.
  ///
  /// Un lote por llamada: con esta conectividad, un envío grande que se corta a
  /// la mitad y hay que repetir entero es peor que varios pequeños. Si quedan
  /// pendientes, se vuelve a pulsar.
  Future<EnvioRealizado> sincronizar() async {
    if (soloLocal) {
      return _anotar(const EnvioRealizado.sinConexion(
          SinConexion('Los datos de demostración no se sincronizan.')));
    }
    final api = _clienteActivo;
    if (api == null) {
      return _anotar(const EnvioRealizado.sinConexion(
          SinConexion('Falta abrir una sesión remota.')));
    }
    if (_enCurso) return _ultimo ?? const EnvioRealizado.nadaQueEnviar();

    _enCurso = true;
    notifyListeners();
    try {
      final cola = ColaDeEnvio(
          repo: _repo,
          api: api,
          dispositivoId: _dispositivoId,
          maxPacientesPorLote:
              api is ClienteFirebase || api is ClienteFirebaseRest ? 1 : null);
      return _anotar(await cola.sincronizar());
    } finally {
      _enCurso = false;
      notifyListeners();
    }
  }

  EnvioRealizado _anotar(EnvioRealizado resultado) {
    _ultimo = resultado;
    notifyListeners();
    return resultado;
  }

  @override
  void dispose() {
    _api?.cerrar();
    _firebase?.cerrar();
    _firebaseRest?.cerrar();
    super.dispose();
  }
}
