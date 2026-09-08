import 'dart:math';

/// Identificadores de registro.
///
/// Aleatorios de 128 bits, no correlativos. Con varios dispositivos capturando
/// sin conexión, unos identificadores del tipo `p-0001` chocarían en cuanto se
/// sincronizara el segundo teléfono: dos pacientes distintos con el mismo id.
/// El coste de equivocarse aquí se paga mucho más tarde y es carísimo.
///
/// **En formato UUID versión 4**, que es lo que la base central declara para
/// cada clave (`api/migraciones/001_esquema_inicial.sql`). Antes llevaban un
/// prefijo por comodidad al leer registros —`p-3f9a…`—, y era el cliente el que
/// tenía que ceder: aflojar el tipo de la columna a texto habría perdido la
/// validación, la mitad del índice y el doble de espacio, a cambio de que un
/// log se leyera algo mejor.
class Ids {
  const Ids._();

  static final Random _azar = Random.secure();

  /// `3f9a2c48-7d61-4e0b-9c2a-5f81b3d7e604`
  static String nuevo() {
    final bytes = List<int>.generate(16, (_) => _azar.nextInt(256));

    // Los cuatro bits de versión y los dos de variante que exige la RFC 4122.
    // Sin ellos PostgreSQL acepta el valor igual —solo mira que sean 128 bits—
    // pero deja de ser un UUIDv4 y cualquier herramienta que lo compruebe lo
    // dirá.
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;

    final hex =
        bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  static final RegExp _uuid = RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-'
      r'[0-9a-f]{12}$',
      caseSensitive: false);

  /// Si este identificador puede viajar al servidor central.
  ///
  /// La base central declara `uuid` en cada clave, así que un identificador
  /// que no lo sea sería rechazado — y con él, el lote entero. Los del juego de
  /// demostración (`p-demo-01`) están escritos así a propósito: **que no se
  /// puedan sincronizar es la propiedad que se quiere**, y comprobarlo aquí
  /// evita que dependa de acordarse.
  static bool esSincronizable(String id) => _uuid.hasMatch(id);
}
