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
      final uid = credencial.user!.uid;
      final perfil = await _firestore.collection('investigadores').doc(uid).get();
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
      return Investigador(
        id: uid,
        usuario: correo,
        nombre: datos['nombre'] as String,
        roles: roles,
        institucion: Institucion(
          codigo: codigo,
          nombre: (datos['institucion_nombre'] as String?) ?? codigo,
        ),
      );
    } on FirebaseAuthException catch (error) {
      throw AccesoFirebaseRechazado(_mensaje(error.code));
    } on FirebaseException catch (error) {
      throw AccesoFirebaseRechazado(error.message ?? 'No se pudo leer el perfil.');
    }
  }

  Future<void> salir() => _auth.signOut();

  static String _mensaje(String codigo) => switch (codigo) {
        'invalid-credential' || 'wrong-password' || 'user-not-found' =>
          'Correo o contraseña incorrectos.',
        'network-request-failed' => 'Sin conexión con Firebase.',
        'too-many-requests' => 'Demasiados intentos. Intente más tarde.',
        _ => 'No se pudo abrir la sesión remota.',
      };
}

class PerfilNoAprovisionado implements Exception {
  const PerfilNoAprovisionado();
  @override
  String toString() => 'Esta cuenta no tiene un perfil aprobado para el estudio.';
}

class AccesoFirebaseRechazado implements Exception {
  const AccesoFirebaseRechazado(this.mensaje);
  final String mensaje;
  @override
  String toString() => mensaje;
}
