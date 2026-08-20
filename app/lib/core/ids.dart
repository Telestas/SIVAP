import 'dart:math';

/// Identificadores de registro.
///
/// Aleatorios de 128 bits, no correlativos. Con varios dispositivos capturando
/// sin conexión, unos identificadores del tipo `p-0001` chocarían en cuanto se
/// sincronizara el segundo teléfono: dos pacientes distintos con el mismo id.
/// El coste de equivocarse aquí se paga mucho más tarde y es carísimo.
class Ids {
  const Ids._();

  static final Random _azar = Random.secure();

  /// `p-3f9a2c...` — el prefijo solo sirve para leer logs con comodidad.
  static String nuevo(String prefijo) {
    final bytes = List<int>.generate(16, (_) => _azar.nextInt(256));
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '$prefijo-$hex';
  }
}
