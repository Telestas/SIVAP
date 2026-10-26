import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../domain/models/institucion.dart';
import '../../domain/models/role.dart';

/// Acceso remoto para la sincronización. No crea cuentas: los perfiles se
/// aprovisionan fuera de la app para que nadie pueda concederse funciones.
class AutenticacionFirebase {
  AutenticacionFirebase({FirebaseAuth? auth, FirebaseFirestore? firestore})
      : _auth = auth ?? FirebaseAuth.instance,
        _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;

  Future<Investigador> entrar(String correo, String contrasena) async {
    try {
      final credencial = await _auth.signInWithEmailAndPassword(
          email: correo, password: contrasena);
      return await _leerPerfil(credencial.user!);
    } on FirebaseAuthException catch (error) {
      throw AccesoFirebaseRechazado(_mensaje(error.code));
    } on FirebaseException catch (error) {
      throw AccesoFirebaseRechazado(
          error.message ?? 'No se pudo leer el perfil.');
    }
  }

  /// Devuelve el perfil de la sesión que Firebase restauró, si existe.
  Future<Investigador?> restaurar() async {
    final usuario = _auth.currentUser;
    if (usuario == null) return null;
    try {
      return await _leerPerfil(usuario);
    } on FirebaseException catch (error) {
      if (error.code == 'unavailable' ||
          error.code == 'network-request-failed') {
        return _leerPerfil(usuario, soloCache: true);
      }
      await _auth.signOut();
      rethrow;
    }
  }

  Future<Investigador> _leerPerfil(User usuario,
      {bool soloCache = false}) async {
    final uid = usuario.uid;
    final perfil = await _firestore
        .collection('investigadores')
        .doc(uid)
        .get(GetOptions(source: soloCache ? Source.cache : Source.server));
    if (!perfil.exists) {
      await _auth.signOut();
      throw const PerfilNoAprovisionado();
    }
    final datos = perfil.data()!;
    final roles = (datos['roles'] as List<dynamic>)
        .map((r) => Rol.values.byName(r as String))
        .toSet();
    if (roles.isEmpty) throw const PerfilNoAprovisionado();
    final codigo = datos['institucion_codigo'] as String;
    var nombreCentro = nombreVisibleCentro(datos, null);
    try {
      final centro = await _firestore
          .collection('instituciones')
          .doc(codigo)
          .get(GetOptions(source: soloCache ? Source.cache : Source.server));
      nombreCentro = nombreVisibleCentro(datos, centro.data());
    } on FirebaseException {
      // El nombre del perfil permite entrar sin red; el código estable sigue
      // controlando el acceso y la separación entre instituciones.
    }
    return Investigador(
      id: uid,
      usuario: usuario.email ?? uid,
      nombre: datos['nombre'] as String,
      roles: roles,
      institucion: Institucion(
        codigo: codigo,
        nombre: nombreCentro,
      ),
    );
  }

  /// El nombre puede cambiar; el código del centro permanece estable.
  static String nombreVisibleCentro(
      Map<String, dynamic> perfil, Map<String, dynamic>? centro) {
    final actual = centro?['nombre'];
    if (actual is String && actual.trim().isNotEmpty) return actual.trim();
    final anterior = perfil['institucion_nombre'];
    if (anterior is String && anterior.trim().isNotEmpty) {
      return anterior.trim();
    }
    return perfil['institucion_codigo'] as String;
  }

  Future<void> salir() => _auth.signOut();

  /// Solicita a Firebase el correo oficial de recuperación.
  ///
  /// Firebase no confirma si la dirección existe, para no facilitar la
  /// enumeración de cuentas. La pantalla muestra por ello el mismo resultado
  /// en ambos casos.
  Future<void> recuperarAcceso(String correo) async {
    try {
      await _auth.sendPasswordResetEmail(email: correo.trim());
    } on FirebaseAuthException catch (error) {
      throw AccesoFirebaseRechazado(_mensajeRecuperacion(error.code));
    }
  }

  static String _mensaje(String codigo) => switch (codigo) {
        'invalid-credential' ||
        'wrong-password' ||
        'user-not-found' =>
          'Correo o contraseña incorrectos.',
        'network-request-failed' => 'Sin conexión con Firebase.',
        'too-many-requests' => 'Demasiados intentos. Intente más tarde.',
        _ => 'No se pudo abrir la sesión remota.',
      };

  static String _mensajeRecuperacion(String codigo) => switch (codigo) {
        'invalid-email' => 'El correo no tiene un formato válido.',
        'network-request-failed' => 'Sin conexión con Firebase.',
        'too-many-requests' => 'Demasiados intentos. Intente más tarde.',
        _ => 'No se pudo solicitar el correo de recuperación.',
      };
}

class PerfilNoAprovisionado implements Exception {
  const PerfilNoAprovisionado();
  @override
  String toString() =>
      'Esta cuenta no tiene un perfil aprobado para el estudio.';
}

class AccesoFirebaseRechazado implements Exception {
  const AccesoFirebaseRechazado(this.mensaje);
  final String mensaje;
  @override
  String toString() => mensaje;
}
