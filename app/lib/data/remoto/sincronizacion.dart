import 'package:flutter/foundation.dart';

import '../../core/ids.dart';
import '../../domain/repositories/study_repository.dart';
import 'cliente_api.dart';
import 'cola_de_envio.dart';
import 'lote.dart';

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
  Sincronizacion(this._repo, {ClienteApi Function(Uri)? construirCliente})
      : _construirCliente =
            construirCliente ?? ((base) => ClienteApi(base: base)) {
    _cargar();
  }

  static const claveServidor = 'servidor_url';
  static const claveDispositivo = 'dispositivo_id';
  static const claveEtiqueta = 'dispositivo_etiqueta';

  final StudyRepository _repo;
  final ClienteApi Function(Uri) _construirCliente;

  ClienteApi? _api;
  Uri? _servidor;
  late String _dispositivoId;

  bool _enCurso = false;
  EnvioRealizado? _ultimo;
  Sesion? _sesion;

  Uri? get servidor => _servidor;
  String get dispositivoId => _dispositivoId;
  bool get enCurso => _enCurso;
  bool get configurado => _servidor != null;
  bool get haySesion => _api?.haySesion ?? false;
  Sesion? get sesion => _sesion;

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

  void salir() {
    _api?.olvidarSesion();
    _sesion = null;
    notifyListeners();
  }

  /// Envía lo pendiente. Devuelve cómo fue, y lo deja anotado para la pantalla.
  ///
  /// Un lote por llamada: con esta conectividad, un envío grande que se corta a
  /// la mitad y hay que repetir entero es peor que varios pequeños. Si quedan
  /// pendientes, se vuelve a pulsar.
  Future<EnvioRealizado> sincronizar() async {
    final api = _api;
    if (api == null) {
      return _anotar(const EnvioRealizado.sinConexion(
          SinConexion('Falta configurar la dirección del servidor.')));
    }
    if (_enCurso) return _ultimo ?? const EnvioRealizado.nadaQueEnviar();

    _enCurso = true;
    notifyListeners();
    try {
      final cola = ColaDeEnvio(
          repo: _repo, api: api, dispositivoId: _dispositivoId);
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
    super.dispose();
  }
}
