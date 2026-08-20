import 'evento_clinico.dart';

/// Definición configurable de los formularios del estudio.
///
/// **Restricción no negociable (CLAUDE.md §5).** Los campos de cada evento son
/// DATOS, no widgets escritos a mano. La pantalla de captura recorre esta
/// estructura y construye los controles; ajustar el protocolo es editar la
/// definición —a futuro, servida por el backend—, no recompilar la app.
class EstudioFormDefinition {
  const EstudioFormDefinition({required this.version, required this.eventos});

  final String version;

  /// Un bloque por tipo de evento con captura. Un tipo sin definición
  /// simplemente no se puede registrar todavía.
  final List<EventoDefinicion> eventos;

  EventoDefinicion? para(TipoEvento tipo) {
    for (final e in eventos) {
      if (e.tipo == tipo) return e;
    }
    return null;
  }

  bool tieneFormulario(TipoEvento tipo) => para(tipo) != null;

  List<TipoEvento> get tiposDefinidos => eventos.map((e) => e.tipo).toList();

  /// Todos los tipos declarados, tengan formulario o no, agrupados por fase.
  /// La línea de tiempo los muestra todos: un hito sin formulario definido
  /// sigue siendo parte del proceso, y esconderlo daría una idea falsa.
  static Map<FaseEstudio, List<TipoEvento>> get porFase => {
        for (final f in FaseEstudio.values) f: TipoEvento.deFase(f),
      };
}

class EventoDefinicion {
  const EventoDefinicion({required this.tipo, required this.secciones});

  final TipoEvento tipo;
  final List<FormSection> secciones;

  Iterable<FieldDefinition> get campos => secciones.expand((s) => s.campos);

  Iterable<FieldDefinition> get obligatorios =>
      campos.where((c) => c.obligatorio);
}

class FormSection {
  const FormSection({required this.titulo, required this.campos});

  final String titulo;
  final List<FieldDefinition> campos;
}

enum FieldType {
  numero,
  texto,
  textoLargo,
  fecha,
  siNo,
  seleccionUnica,
  seleccionMultiple,
}

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
    this.ancho = 1,
    this.ayuda,
  });

  /// Identificador estable del campo. Es la columna en el `.xlsx` exportado:
  /// renombrar el `label` es cosmético, renombrar el `key` rompe el dataset.
  final String key;
  final String label;
  final FieldType tipo;
  final String? unidad;
  final bool obligatorio;

  /// Rango de plausibilidad clínica. Fuera de él la app **avisa pero no
  /// bloquea** (CLAUDE.md §14): un valor extremo real —y en UCI los hay— tiene
  /// que poder registrarse. Bloquear un dato verdadero corrompe el dataset más
  /// que admitir un tecleo, que la auditoría permite corregir.
  final num? min;
  final num? max;
  final int decimales;

  final List<String> opciones;

  /// Columnas que ocupa en la retícula de dos columnas (1 o 2).
  final int ancho;

  /// Aclaración breve bajo la etiqueta, para campos que se prestan a confusión.
  final String? ayuda;

  String get etiquetaConUnidad => unidad == null ? label : '$label ($unidad)';

  /// `null` si el valor es aceptable; si no, el aviso a mostrar.
  String? fueraDeRango(Object? valor) {
    if (valor is! num || (min == null && max == null)) return null;
    if (min != null && valor < min!) return 'fuera de rango';
    if (max != null && valor > max!) return 'fuera de rango';
    return null;
  }

}
