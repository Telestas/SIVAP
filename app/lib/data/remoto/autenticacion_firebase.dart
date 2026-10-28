import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../domain/models/institucion.dart';
import '../../domain/models/role.dart';
import 'autenticacion_remota.dart';

/// Acceso remoto. Una cuenta nueva no recibe funciones hasta su aprobación.
class AutenticacionFirebase implements AutenticacionRemota {
  AutenticacionFirebase({FirebaseAuth? auth, FirebaseFirestore? firestore})
      : _auth = auth ?? FirebaseAuth.instance,
        _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;

  @override
  Future<void> crearCuenta(String correo, String contrasena) async {
    try {
      final credencial = await _auth.createUserWithEmailAndPassword(
          email: correo.trim(), password: contrasena);
      await credencial.user!.sendEmailVerification();
    } on FirebaseAuthException catch (error) {
      if (error.code == 'email-already-in-use') {
        throw const CuentaYaExiste();
      }
      throw AccesoFirebaseRechazado(
          mensajeAutenticacion(error.code, detalle: error.message));
    } finally {
      await _auth.signOut();
    }
  }

  @override
  Future<void> solicitarAcceso(String correo, String contrasena, String nombre,
      String codigoCentro) async {
    try {
      final credencial = await _auth.signInWithEmailAndPassword(
          email: correo.trim(), password: contrasena);
      final usuario = credencial.user!;
      await usuario.reload();
      final actual = _auth.currentUser!;
      await actual.getIdToken(true);
      if (!actual.emailVerified) {
        await actual.sendEmailVerification();
        throw const AccesoFirebaseRechazado(
            'Verifique su correo y vuelva a solicitar acceso. Enviamos un nuevo enlace.');
      }
      if ((await _firestore.collection('investigadores').doc(actual.uid).get())
          .exists) {
        throw const AccesoFirebaseRechazado('Esta cuenta ya está aprobada.');
      }
      final referencia =
          _firestore.collection('solicitudes_acceso').doc(actual.uid);
      if ((await referencia.get()).exists) {
        throw const AccesoFirebaseRechazado(
            'Su solicitud ya fue registrada. Espere la decisión del investigador principal.');
      }
      await referencia.set({
        'correo': actual.email,
        'nombre': nombre.trim(),
        'institucion_codigo': codigoCentro.trim(),
        'estado': 'pendiente',
        'solicitado_en': FieldValue.serverTimestamp(),
      });
    } on FirebaseAuthException catch (error) {
      throw AccesoFirebaseRechazado(
          mensajeAutenticacion(error.code, detalle: error.message));
    } on FirebaseException catch (error) {
      throw AccesoFirebaseRechazado(error.code == 'permission-denied'
          ? 'No se pudo registrar la solicitud. Compruebe el código del centro.'
          : (error.message ?? 'No se pudo registrar la solicitud.'));
    } finally {
      await _auth.signOut();
    }
  }

  @override
  Future<Investigador> entrar(String correo, String contrasena) async {
    try {
      final credencial = await _auth.signInWithEmailAndPassword(
          email: correo.trim(), password: contrasena);
      return await _leerPerfil(credencial.user!);
    } on FirebaseAuthException catch (error) {
      throw AccesoFirebaseRechazado(
          mensajeAutenticacion(error.code, detalle: error.message));
    } on FirebaseException catch (error) {
      throw AccesoFirebaseRechazado(
          error.message ?? 'No se pudo leer el perfil.');
    }
  }

  /// Devuelve el perfil de la sesión que Firebase restauró, si existe.
  @override
  Future<Investigador?> restaurar() async {
    final usuario = _auth.currentUser;
    if (usuario == null) return null;
    try {
      return await _leerPerfil(usuario);
    } on FirebaseException catch (error) {
      if (errorPermiteCache(error.code)) {
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

  @override
  Future<void> salir() => _auth.signOut();

  /// Solicita a Firebase el correo oficial de recuperación.
  ///
  /// Firebase no confirma si la dirección existe, para no facilitar la
  /// enumeración de cuentas. La pantalla muestra por ello el mismo resultado
  /// en ambos casos.
  @override
  Future<void> recuperarAcceso(String correo) async {
    try {
      await _auth.sendPasswordResetEmail(email: correo.trim());
    } on FirebaseAuthException catch (error) {
      throw AccesoFirebaseRechazado(_mensajeRecuperacion(error.code));
    }
  }

  /// Android puede entregar UNKNOWN para una falla que el plugin no clasificó.
  /// Mostrar el mensaje nativo permite distinguir red, servicio y credenciales.
  static String mensajeAutenticacion(String codigo, {String? detalle}) {
    if (codigo.toLowerCase() == 'unknown') {
      final texto = detalle?.trim();
      final respuestaHtml = texto?.toLowerCase() ?? '';
      if (respuestaHtml.contains('403') &&
          (respuestaHtml.contains('<!doctype html') ||
              respuestaHtml.contains('<html'))) {
        return 'Firebase rechazó la conexión de este teléfono (HTTP 403). '
            'No indica que el correo o la contraseña sean incorrectos. '
            'Si está en Cuba, pruebe con la VPN para acceder al servicio.';
      }
      return texto == null || texto.isEmpty
          ? 'Firebase no pudo completar el acceso. Compruebe la conexión e inténtelo de nuevo (UNKNOWN).'
          : 'Firebase no pudo completar el acceso: $texto';
    }
    return _mensaje(codigo);
  }

  /// Solo conserva la sesión previamente validada; nunca crea un perfil local.
  static bool errorPermiteCache(String codigo) => const {
        'unavailable',
        'network-request-failed',
        'unknown'
      }.contains(codigo.toLowerCase());

  static String _mensaje(String codigo) => switch (codigo) {
        'invalid-credential' ||
        'wrong-password' ||
        'user-not-found' =>
          'Correo o contraseña incorrectos.',
        'network-request-failed' =>
          'No se pudo conectar con Firebase. Si está en Cuba y el navegador '
              'muestra HTTP 403 en identitytoolkit.googleapis.com, pruebe con '
              'la VPN y vuelva a intentarlo.',
        'email-already-in-use' => 'El correo ya tiene una cuenta.',
        'weak-password' => 'La contraseña debe tener al menos seis caracteres.',
        'invalid-email' => 'El correo no tiene un formato válido.',
        'operation-not-allowed' =>
          'El acceso con correo y contraseña no está habilitado en Firebase.',
        'too-many-requests' => 'Demasiados intentos. Intente más tarde.',
        _ => 'No se pudo abrir la sesión remota (Firebase: $codigo).',
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
      'Esta cuenta no tiene un perfil aprobado. Pulse «Solicitar acceso o crear cuenta».';
}

class AccesoFirebaseRechazado implements Exception {
  const AccesoFirebaseRechazado(this.mensaje);
  final String mensaje;
  @override
  String toString() => mensaje;
}

/// Permite continuar el mismo formulario con una cuenta ya registrada.
class CuentaYaExiste implements Exception {
  const CuentaYaExiste();
}
