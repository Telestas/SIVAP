/// Rama del ensayo.
///
/// **Restricción no negociable (CLAUDE.md §2).** El sistema conoce dos ramas,
/// A y B, y nada más. Cuál de las dos es LIVERE y cuál el manejo convencional
/// NO está en el código, ni en la base de datos, ni en las exportaciones, ni
/// en los logs: vive en el expediente del estudio, en custodia de la
/// investigadora principal, y se revela una sola vez al cierre.
///
/// Está prohibido añadir aquí un campo que describa la rama —"control",
/// "experimental", "nuevo", "vigente"— por útil que parezca. El médico que
/// aplica el protocolo y el que evalúa los desenlaces deben ser incapaces de
/// distinguirlas: si la app lo revela, el ensayo pierde validez interna.
///
/// `test/cegamiento_test.dart` lo comprueba. Si esa prueba falla, no se relaja
/// la aserción: se corrige el código.
enum Protocolo {
  a('PROT. A', 'PROTOCOLO A'),
  b('PROT. B', 'PROTOCOLO B');

  const Protocolo(this.chip, this.nombreLargo);

  /// Distintivo corto, para tarjetas y tablas.
  final String chip;

  /// Forma larga, para el panel de asignación.
  final String nombreLargo;

  /// 'A' o 'B'. Es lo que sale en el dataset exportado.
  String get letra => name.toUpperCase();
}
