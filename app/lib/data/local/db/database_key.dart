import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Custodia de la clave de cifrado de la base de datos local.
///
/// El punto delicado de cifrar en reposo no es cifrar: es dónde queda la clave.
/// Una clave escrita en el código de la app no cifra nada — está dentro del
/// mismo .apk que cualquiera puede abrir. Aquí la clave:
///
/// - se genera en el propio dispositivo, la primera vez que se abre la app;
/// - es de 256 bits, de una fuente criptográficamente segura;
/// - se guarda en el almacén seguro del sistema operativo (Keystore en
///   Android, Keychain en iOS), que en equipos modernos está respaldado por
///   hardware y no es legible por otras apps;
/// - nunca sale del dispositivo, ni se sincroniza, ni se registra en un log.
///
/// Consecuencia asumida: si el usuario desinstala la app o borra sus datos, la
/// clave desaparece y lo que hubiera sin sincronizar es irrecuperable. Es el
/// comportamiento correcto — la alternativa sería poder descifrar los datos sin
/// el dispositivo, que es justo lo que se quiere evitar.
class DatabaseKey {
  const DatabaseKey._();

  /// Versionada: si algún día hay que rotar la clave, la entrada nueva convive
  /// con la vieja el tiempo que dure la migración.
  static const String entradaAlmacen = 'sivap.db.key.v1';

  static const _opcionesAndroid =
      AndroidOptions(encryptedSharedPreferences: true);
  static const _opcionesIos =
      IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device);

  static const FlutterSecureStorage almacenPorDefecto = FlutterSecureStorage(
    aOptions: _opcionesAndroid,
    iOptions: _opcionesIos,
  );

  /// Devuelve la clave del dispositivo, creándola si es la primera vez.
  ///
  /// La clave se devuelve en hexadecimal porque es el formato que SQLCipher
  /// acepta como clave en bruto (`PRAGMA key = "x'...'"`), sin pasar por
  /// derivación por contraseña: no hace falta derivar nada de 256 bits que ya
  /// son aleatorios.
  static Future<String> obtenerOCrear({
    FlutterSecureStorage almacen = almacenPorDefecto,
  }) async {
    final existente = await almacen.read(key: entradaAlmacen);
    if (existente != null && _esHexDe32Bytes(existente)) return existente;

    final nueva = generar();
    await almacen.write(key: entradaAlmacen, value: nueva);
    return nueva;
  }

  /// Genera una clave nueva de 256 bits.
  ///
  /// Usa [Random.secure] — la fuente del sistema operativo. Nótese el contraste
  /// deliberado con la aleatorización del estudio, que usa un generador
  /// reproducible desde una semilla: allí la reproducibilidad es un requisito
  /// de auditoría; aquí sería un fallo de seguridad. No unificar los dos.
  static String generar() {
    final azar = Random.secure();
    final bytes = List<int>.generate(32, (_) => azar.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  static bool _esHexDe32Bytes(String v) =>
      v.length == 64 && RegExp(r'^[0-9a-f]+$').hasMatch(v);
}
