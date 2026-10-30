import '../../domain/models/institucion.dart';
import '../../domain/models/role.dart';
import 'autenticacion_firebase.dart';
import 'autenticacion_remota.dart';
import 'firebase_rest_movil.dart';

/// Autenticación Android por Cloudflare; Firebase sigue validando la cuenta.
class AutenticacionRestMovil implements AutenticacionRemota {
  AutenticacionRestMovil(this.rest);
  final FirebaseRestMovil rest;

  @override
  Future<void> crearCuenta(String correo, String contrasena) async {
    try {
      await rest.crearCuenta(correo, contrasena);
    } on FirebaseRestError catch (error) {
      if (error.codigo == 'EMAIL_EXISTS') throw const CuentaYaExiste();
      throw AccesoFirebaseRechazado(error.mensaje);
    }
  }

  @override
  Future<void> solicitarAcceso(String correo, String contrasena, String nombre,
      String codigoCentro) async {
    try {
      await rest.entrar(correo, contrasena);
      final cuenta = await rest.datosCuenta();
      final verificada = cuenta['emailVerified'] == true;
      final uid = rest.uid!;
      if (await rest.leer('investigadores/$uid') != null) {
        throw const AccesoFirebaseRechazado('Esta cuenta ya está aprobada.');
      }
      final anterior = await rest.leer('solicitudes_acceso/$uid');
      if (anterior != null) {
        if (anterior['institucion_codigo'] != codigoCentro.trim() ||
            anterior['nombre'] != nombre.trim()) {
          throw const AccesoFirebaseRechazado(
              'Este correo ya tiene una solicitud con otros datos. '
              'Consulte al investigador principal de su centro.');
        }
        if (anterior['estado'] == 'pendiente_verificacion' && verificada) {
          await rest.escribir(
              'solicitudes_acceso/$uid', {'estado': 'pendiente'},
              fusionar: true);
        } else if (!verificada) {
          throw const VerificacionPendiente();
        }
        return;
      }
      if (!verificada) await rest.enviarCorreoVerificacion();
      // El tiempo del servidor es obligatorio para cumplir las reglas.
      await rest.escribir(
          'solicitudes_acceso/$uid',
          {
            'correo': cuenta['email'] as String,
            'nombre': nombre.trim(),
            'institucion_codigo': codigoCentro.trim(),
            'estado': verificada ? 'pendiente' : 'pendiente_verificacion',
            'solicitado_en': null,
          },
          crear: true,
          marcaTiempo: true);
      if (!verificada) throw const VerificacionPendiente();
    } on FirebaseRestError catch (error) {
      throw AccesoFirebaseRechazado(error.estado == 403
          ? 'No se pudo registrar la solicitud. Compruebe el código del centro.'
          : error.mensaje);
    } finally {
      await rest.salir();
    }
  }

  @override
  Future<Investigador> entrar(String correo, String contrasena) async {
    try {
      await rest.entrar(correo, contrasena);
      final cuenta = await rest.datosCuenta();
      if (cuenta['emailVerified'] == true) {
        final uid = rest.uid!;
        final solicitud = await rest.leer('solicitudes_acceso/$uid');
        if (solicitud?['estado'] == 'pendiente_verificacion') {
          await rest.escribir(
              'solicitudes_acceso/$uid', {'estado': 'pendiente'},
              fusionar: true);
        }
      }
      return await _leerPerfil();
    } on FirebaseRestError catch (error) {
      throw AccesoFirebaseRechazado(error.mensaje);
    }
  }

  @override
  Future<Investigador?> restaurar() async {
    try {
      await rest.restaurarToken();
      if (!rest.haySesion) return null;
      return await _leerPerfil();
    } on FirebaseRestError catch (error) {
      if (error.estado == 0 || error.estado == 502 || error.estado == 503) {
        return rest.perfilGuardado();
      }
      await rest.salir();
      rethrow;
    }
  }

  Future<Investigador> _leerPerfil() async {
    final uid = rest.uid!;
    final datos = await rest.leer('investigadores/$uid');
    if (datos == null) {
      await rest.salir();
      throw const PerfilNoAprovisionado();
    }
    final roles = (datos['roles'] as List<dynamic>)
        .map((r) => Rol.values.byName(r as String))
        .toSet();
    if (roles.isEmpty) throw const PerfilNoAprovisionado();
    final codigo = datos['institucion_codigo'] as String;
    Map<String, dynamic>? centro;
    try {
      centro = await rest.leer('instituciones/$codigo');
    } on FirebaseRestError {
      // El nombre del perfil sigue siendo suficiente con conexión débil.
    }
    final cuenta = await rest.datosCuenta();
    final investigador = Investigador(
      id: uid,
      usuario: (cuenta['email'] as String?) ?? uid,
      nombre: datos['nombre'] as String,
      roles: roles,
      institucion: Institucion(
        codigo: codigo,
        nombre: AutenticacionFirebase.nombreVisibleCentro(datos, centro),
      ),
    );
    await rest.guardarPerfil(investigador);
    return investigador;
  }

  @override
  Future<void> salir() => rest.salir();

  @override
  Future<void> recuperarAcceso(String correo) async {
    try {
      await rest.recuperarAcceso(correo);
    } on FirebaseRestError catch (error) {
      throw AccesoFirebaseRechazado(error.mensaje);
    }
  }
}
