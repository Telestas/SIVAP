/// Definición configurable de los formularios de visita.
///
/// Restricción no negociable (CLAUDE.md §3): los campos de cada visita son
/// DATOS, no widgets escritos a mano. La pantalla de captura recorre esta
/// estructura y construye los controles; ajustar el protocolo es editar esta
/// definición (a futuro, servida por el backend), no recompilar la app.
class VisitFormDefinition {
  const VisitFormDefinition({
    required this.version,
    required this.diasVisita,
    required this.secciones,
  });

  final String version;

  /// Índices de visita del estudio. Ajustables — el diseño asume 1, 3, 5, 10, 14
  /// pero nada en el código depende de esos números concretos.
  final List<int> diasVisita;

  final List<FormSection> secciones;

  /// Secciones con al menos un campo aplicable al día [dia].
  List<FormSection> seccionesPara(int dia) => secciones
      .map((s) => s.filtradaPara(dia))
      .where((s) => s.campos.isNotEmpty)
      .toList();

  Iterable<FieldDefinition> camposPara(int dia) =>
      secciones.expand((s) => s.campos).where((c) => c.aplicaA(dia));
}

class FormSection {
  const FormSection({required this.titulo, required this.campos});
  final String titulo;
  final List<FieldDefinition> campos;

  FormSection filtradaPara(int dia) => FormSection(
      titulo: titulo, campos: campos.where((c) => c.aplicaA(dia)).toList());
}

enum FieldType { numero, texto, textoLargo, fecha, seleccionMultiple, seleccionUnica }

class FieldDefinition {
  const FieldDefinition({
    required this.key,
    required this.label,
    required this.tipo,
    this.unidad,
    this.obligatorio = false,
    this.min,
    this.max,
    this.decimales = 0,
    this.opciones = const [],
    this.dias,
    this.ancho = 1,
  });

  /// Identificador estable del campo. Es la columna en el .xlsx exportado:
  /// renombrar el `label` es cosmético, renombrar el `key` rompe el dataset.
  final String key;
  final String label;
  final FieldType tipo;
  final String? unidad;
  final bool obligatorio;

  /// Rango clínico plausible. Fuera de él la app AVISA pero no bloquea: un
  /// valor extremo real debe poder registrarse (CLAUDE.md — el dato manda).
  final num? min;
  final num? max;
  final int decimales;

  final List<String> opciones;

  /// Días en los que se recoge este campo. `null` = en todos.
  final List<int>? dias;

  /// Columnas que ocupa en la retícula de dos columnas (1 o 2).
  final int ancho;

  bool aplicaA(int dia) => dias == null || dias!.contains(dia);

  String get etiquetaConUnidad => unidad == null ? label : '$label ($unidad)';

  /// `null` si el valor es aceptable; si no, el aviso a mostrar.
  String? fueraDeRango(Object? valor) {
    if (valor is! num || (min == null && max == null)) return null;
    if (min != null && valor < min!) return 'fuera de rango';
    if (max != null && valor > max!) return 'fuera de rango';
    return null;
  }
}
