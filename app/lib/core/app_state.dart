import 'package:flutter/foundation.dart';

import '../data/local/in_memory_study_repository.dart';
import '../domain/models/role.dart';
import '../domain/repositories/study_repository.dart';

/// Estado de sesión de la app.
///
/// Sin paquetes de terceros a propósito: la app debe compilarse en una máquina
/// sin acceso fiable a pub.dev. `ChangeNotifier` del SDK sobra para este tamaño.
class AppState extends ChangeNotifier {
  AppState() : repo = InMemoryStudyRepository();

  final StudyRepository repo;

  Investigador? _usuario;
  Investigador? get usuario => _usuario;
  Investigador get usuarioActual => _usuario!;

  /// Modo sin conexión. En el MVP es un interruptor manual para poder
  /// demostrar el comportamiento offline; después lo dictará la conectividad
  /// real. La captura de datos NO depende de esto en ningún caso
  /// (CLAUDE.md §7): sin conexión se trabaja igual, solo cambia el envío.
  bool sinConexion = true;

  void iniciarSesion(Investigador investigador) {
    _usuario = investigador;
    notifyListeners();
  }

  void cerrarSesion() {
    _usuario = null;
    notifyListeners();
  }

  void alternarConexion() {
    sinConexion = !sinConexion;
    notifyListeners();
  }

  int get enCola => sinConexion ? repo.registrosEnCola : 0;

  String get textoSync => sinConexion
      ? '$enCola ${enCola == 1 ? 'visita pendiente' : 'visitas pendientes'} de envío'
      : 'Datos al día · sincronizado 09:01';

  String get textoSyncCorto => sinConexion ? '$enCola en cola' : 'AL DÍA';

  /// Refresca tras una escritura en el repositorio.
  void refrescar() => notifyListeners();
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
