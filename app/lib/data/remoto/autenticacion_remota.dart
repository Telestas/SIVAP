import '../../domain/models/role.dart';

/// Operaciones de acceso compartidas por web y Android.
abstract class AutenticacionRemota {
  Future<void> crearCuenta(String correo, String contrasena);
  Future<void> solicitarAcceso(
      String correo, String contrasena, String nombre, String codigoCentro);
  Future<Investigador> entrar(String correo, String contrasena);
  Future<Investigador?> restaurar();
  Future<void> salir();
  Future<void> recuperarAcceso(String correo);
}
