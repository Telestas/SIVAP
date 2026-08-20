/// Centro participante en el ensayo.
///
/// **Restricción no negociable (CLAUDE.md §8).** El ensayo es multicéntrico:
/// ficha, evento clínico y usuario declaran a qué centro pertenecen. Los
/// análisis por centro y el control de contaminación entre grupos dependen de
/// ello, y sin este dato no se pueden hacer después.
///
/// El catálogo real de centros es **configuración del estudio**, no código: los
/// nombres de los hospitales no se versionan (CLAUDE.md §15). Lo que hay en
/// `Seed.instituciones` son descriptores genéricos para poder demostrar la app.
class Institucion {
  const Institucion({
    required this.codigo,
    required this.nombre,
    this.coordinador = false,
  });

  /// Prefijo del código de paciente y clave de agrupación en los análisis.
  /// Corto y estable: cambiarlo rompería los códigos ya emitidos.
  final String codigo;

  final String nombre;

  /// Si es el centro coordinador del ensayo.
  final bool coordinador;

  @override
  bool operator ==(Object other) =>
      other is Institucion && other.codigo == codigo;

  @override
  int get hashCode => codigo.hashCode;

  @override
  String toString() => nombre;
}
