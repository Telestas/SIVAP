/// Utilidades de colección mínimas.
///
/// `firstOrNull` existe en `package:collection`, pero el proyecto no arrastra
/// dependencias externas (ver `pubspec.yaml`). Nombre distinto al de la
/// extensión del paquete para que no haya ambigüedad si algún día entra.
extension PrimeroONulo<E> on Iterable<E> {
  /// El primer elemento, o `null` si la colección está vacía.
  E? get primero {
    final it = iterator;
    return it.moveNext() ? it.current : null;
  }

  /// El primer elemento que cumple [prueba], o `null` si ninguno lo hace.
  E? primeroQue(bool Function(E) prueba) {
    for (final e in this) {
      if (prueba(e)) return e;
    }
    return null;
  }
}
