import 'package:flutter/widgets.dart';

import '../data/local/almacen_local.dart';
import '../data/local/in_memory_study_repository.dart';
import '../data/remoto/sincronizacion.dart';
import '../domain/models/role.dart';
import '../domain/repositories/study_repository.dart';

/// Estado de sesión de la app.
class AppState extends ChangeNotifier {
  AppState(this.almacen, {Sincronizacion? sincronizacion})
      : sincronizacion = sincronizacion ?? Sincronizacion(almacen.repo) {
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

  /// A qué servidor habla este aparato y qué le falta por enviar.
  final Sincronizacion sincronizacion;

  StudyRepository get repo => almacen.repo;

  Investigador? _usuario;
  Investigador? get usuario => _usuario;
  Investigador get usuarioActual => _usuario!;

  void iniciarSesion(Investigador investigador) {
    _usuario = investigador;
    notifyListeners();
  }

  void cerrarSesion() {
    _usuario = null;
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
