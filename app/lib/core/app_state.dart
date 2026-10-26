import 'dart:async';

import 'package:flutter/widgets.dart';

import '../data/local/almacen_local.dart';
import '../data/local/in_memory_study_repository.dart';
import '../data/remoto/sincronizacion.dart';
import '../domain/models/role.dart';
import '../domain/repositories/study_repository.dart';

typedef AutenticarUsuario = Future<Investigador> Function(
    String usuario, String contrasena);
typedef CargarRepositorioRemoto = Future<StudyRepository> Function(
    Investigador investigador);
typedef CerrarSesionRemota = Future<void> Function();
typedef RecuperarAccesoRemoto = Future<void> Function(String correo);
typedef CrearCuentaRemota = Future<void> Function(
    String correo, String contrasena);
typedef SolicitarAccesoRemoto = Future<void> Function(
    String correo, String contrasena, String nombre, String codigoCentro);

/// Estado de sesión de la app.
class AppState extends ChangeNotifier {
  AppState(
    this.almacen, {
    Sincronizacion? sincronizacion,
    AutenticarUsuario? autenticarUsuario,
    CargarRepositorioRemoto? cargarRepositorioRemoto,
    CerrarSesionRemota? cerrarSesionRemota,
    RecuperarAccesoRemoto? recuperarAccesoRemoto,
    CrearCuentaRemota? crearCuentaRemota,
    SolicitarAccesoRemoto? solicitarAccesoRemoto,
  })  : _repo = almacen.repo,
        _autenticarUsuario = autenticarUsuario,
        _cargarRepositorioRemoto = cargarRepositorioRemoto,
        _cerrarSesionRemota = cerrarSesionRemota,
        _recuperarAccesoRemoto = recuperarAccesoRemoto,
        _crearCuentaRemota = crearCuentaRemota,
        _solicitarAccesoRemoto = solicitarAccesoRemoto,
        sincronizacion = sincronizacion ?? Sincronizacion(almacen.repo) {
    // Lo que pasa en la sincronización cambia lo que se ve en pantalla: el
    // contador de la cola, sobre todo.
    this.sincronizacion.addListener(notifyListeners);
  }

  /// Almacén volátil, para pruebas y para el arranque en navegador.
  factory AppState.enMemoria() => AppState(AlmacenLocal(
        repo: InMemoryStudyRepository(),
        persistente: false,
        cifrado: false,
        descripcion: 'En memoria',
        advertencia: 'Almacén en memoria: los datos se pierden al cerrar.',
      ));

  final AlmacenLocal almacen;
  StudyRepository _repo;
  final AutenticarUsuario? _autenticarUsuario;
  final CargarRepositorioRemoto? _cargarRepositorioRemoto;
  final CerrarSesionRemota? _cerrarSesionRemota;
  final RecuperarAccesoRemoto? _recuperarAccesoRemoto;
  final CrearCuentaRemota? _crearCuentaRemota;
  final SolicitarAccesoRemoto? _solicitarAccesoRemoto;

  /// A qué servidor habla este aparato y qué le falta por enviar.
  final Sincronizacion sincronizacion;

  StudyRepository get repo => _repo;

  bool get requiereAutenticacionRemota => _autenticarUsuario != null;

  Future<void> crearCuenta(String correo, String contrasena) async {
    final crear = _crearCuentaRemota;
    if (crear == null) {
      throw StateError('El registro remoto no está configurado.');
    }
    await crear(correo, contrasena);
  }

  Future<void> solicitarAcceso(String correo, String contrasena, String nombre,
      String codigoCentro) async {
    final solicitar = _solicitarAccesoRemoto;
    if (solicitar == null) {
      throw StateError('La solicitud de acceso no está configurada.');
    }
    await solicitar(correo, contrasena, nombre, codigoCentro);
  }

  Future<void> recuperarAcceso(String correo) async {
    final recuperar = _recuperarAccesoRemoto;
    if (recuperar == null) {
      throw StateError('La recuperación remota no está configurada.');
    }
    await recuperar(correo);
  }

  Investigador? _usuario;
  Investigador? get usuario => _usuario;
  Investigador get usuarioActual => _usuario!;

  void iniciarSesion(Investigador investigador) {
    _usuario = investigador;
    notifyListeners();
  }

  /// Autentica y carga la vista remota antes de abrir el panel.
  ///
  /// No se publica una sesión a medias: si Firestore rechaza la lectura, la
  /// aplicación permanece en el acceso y no conserva un rol sin datos.
  Future<void> iniciarSesionRemota(String usuario, String contrasena) async {
    final autenticar = _autenticarUsuario;
    final cargar = _cargarRepositorioRemoto;
    if (autenticar == null || cargar == null) {
      throw StateError('La autenticación remota no está configurada.');
    }
    final investigador = await autenticar(usuario, contrasena);
    await _verificarAparato(investigador);
    final repositorio = await cargar(investigador);
    _repo = repositorio;
    _usuario = investigador;
    if (almacen.persistente) sincronizacion.vincularFirebase(investigador);
    notifyListeners();
  }

  /// Restaura una sesión que Firebase ya mantenía abierta en el navegador.
  Future<void> restaurarSesionRemota(Investigador investigador) async {
    final cargar = _cargarRepositorioRemoto;
    if (cargar == null) return;
    await _verificarAparato(investigador);
    _repo = await cargar(investigador);
    _usuario = investigador;
    if (almacen.persistente) sincronizacion.vincularFirebase(investigador);
  }

  /// La base cifrada pertenece a una sola cuenta. Reutilizar el aparato con
  /// otra cuenta expondría los pacientes guardados sin sincronizar.
  Future<void> _verificarAparato(Investigador investigador) async {
    if (!almacen.persistente) return;
    const clave = 'propietario_uid';
    final anterior = almacen.repo.ajuste(clave);
    if (anterior != null && anterior != investigador.id) {
      await _cerrarSesionRemota?.call();
      throw StateError(
          'Este aparato está vinculado a otra cuenta del estudio.');
    }
    if (anterior == null) almacen.repo.guardarAjuste(clave, investigador.id);
  }

  void cerrarSesion() {
    _usuario = null;
    _repo = almacen.repo;
    sincronizacion.salir();
    final cerrar = _cerrarSesionRemota;
    if (cerrar != null) unawaited(cerrar());
    notifyListeners();
  }

  /// Cuántos registros esperan a salir del aparato.
  ///
  /// Sale del almacén, no de un interruptor: es cierto aunque nunca se haya
  /// hablado con el servidor, que es justo cuando importa saberlo.
  int get enCola => sincronizacion.pendientes;

  bool get hayCola => enCola > 0;

  String get textoSync => hayCola
      ? '$enCola ${enCola == 1 ? 'registro pendiente' : 'registros pendientes'} '
          'de envío'
      : 'Todo enviado al servidor';

  String get textoSyncCorto => hayCola ? '$enCola en cola' : 'AL DÍA';

  /// Refresca tras una escritura en el repositorio.
  void refrescar() => notifyListeners();

  @override
  void dispose() {
    sincronizacion.removeListener(notifyListeners);
    super.dispose();
  }
}

/// Acceso al [AppState] desde cualquier punto del árbol.
class AppScope extends InheritedNotifier<AppState> {
  const AppScope({super.key, required AppState state, required super.child})
      : super(notifier: state);

  static AppState of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppScope>()!.notifier!;

  /// Lectura sin suscripción, para manejadores de eventos.
  static AppState read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<AppScope>()!.notifier!;
}
