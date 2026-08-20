/// Formato de fechas y números en español, sin `intl`.
///
/// Se evita el paquete a propósito: la app debe poder compilarse en una máquina
/// sin acceso fiable a pub.dev, y aquí solo hacen falta cuatro formatos.
class F {
  const F._();

  static const _meses = [
    'ene', 'feb', 'mar', 'abr', 'may', 'jun',
    'jul', 'ago', 'sep', 'oct', 'nov', 'dic'
  ];

  /// "24 ago"
  static String diaMes(DateTime d) => '${d.day} ${_meses[d.month - 1]}';

  /// "24 ago 2026"
  static String fechaLarga(DateTime d) => '${diaMes(d)} ${d.year}';

  /// "20 ago 08:12"
  static String fechaHora(DateTime d) => '${diaMes(d)} ${hora(d)}';

  /// "08:12"
  static String hora(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  /// Días de diferencia en fechas de calendario, ignorando la hora.
  static int diasEntre(DateTime desde, DateTime hasta) =>
      DateTime(hasta.year, hasta.month, hasta.day)
          .difference(DateTime(desde.year, desde.month, desde.day))
          .inDays;

  /// "vence hoy", "vence mañana", "venció hace 2 días", "24 ago".
  static String vencimiento(DateTime programada, DateTime hoy) {
    final d = diasEntre(hoy, programada);
    return switch (d) {
      0 => 'vence hoy',
      1 => 'vence mañana',
      -1 => 'venció ayer',
      < -1 => 'venció hace ${-d} días',
      _ => diaMes(programada),
    };
  }

  /// Número con los decimales que pide la definición del campo.
  static String numero(num v, int decimales) =>
      decimales == 0 ? v.round().toString() : v.toStringAsFixed(decimales);
}
