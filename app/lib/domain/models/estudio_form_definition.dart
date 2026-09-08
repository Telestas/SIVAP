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

  /// La sección que decide si el paciente puede entrar al estudio, si la hay.
  FormSection? get puertaDeExclusion {
    for (final s in secciones) {
      if (s.esPuertaDeExclusion) return s;
    }
    return null;
  }

  /// Campos visibles con estos valores capturados.
  ///
  /// Lo que no se ve tampoco se exige: un campo oculto no puede ser
  /// obligatorio, o el formulario quedaría bloqueado por algo que la pantalla
  /// ni siquiera muestra.
  Iterable<FieldDefinition> visibles(Map<String, Object?> valores) =>
      campos.where((c) => c.visibleCon(valores));

  Iterable<FieldDefinition> obligatoriosVisibles(Map<String, Object?> valores) =>
      visibles(valores).where((c) => c.obligatorio);
}

class FormSection {
  const FormSection({
    required this.titulo,
    required this.campos,
    this.esPuertaDeExclusion = false,
    this.mensajeAlExcluir,
  });

  final String titulo;
  final List<FieldDefinition> campos;

  /// Si esta sección decide la elegibilidad **antes** de enrolar.
  ///
  /// Marcar uno solo de sus campos detiene el enrolamiento: no se piden los
  /// datos del paciente, no se consume posición de la secuencia de
  /// aleatorización y no se crea ficha. Es la diferencia entre un paciente que
  /// no entró y uno que entró y hubo que sacar — el segundo deja rastro en el
  /// estudio y el primero no debe dejarlo.
  final bool esPuertaDeExclusion;

  /// Qué se le dice a quien recluta cuando marca un criterio.
  final String? mensajeAlExcluir;

  /// Los criterios marcados, en el orden de la definición.
  List<FieldDefinition> criteriosMarcados(Map<String, Object?> valores) {
    if (!esPuertaDeExclusion) return const [];
    return campos.where((c) => valores[c.key] == true).toList();
  }

  bool excluye(Map<String, Object?> valores) =>
      criteriosMarcados(valores).isNotEmpty;
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

/// Cálculos que la app sabe hacer sobre otros campos del mismo formulario.
///
/// Van como valores de un enum y no como una fórmula escrita en la definición.
/// Una fórmula en texto obligaría a escribir un intérprete —un lenguaje
/// pequeño, con sus propios errores— para ahorrar tres funciones. Cuando el
/// protocolo pida un cálculo nuevo, se añade aquí; es la única parte del
/// formulario que no se puede cambiar sin recompilar, y conviene que sea
/// pequeña y explícita.
enum Calculo {
  /// Peso en kg y talla en metros → índice de masa corporal.
  imc,

  /// IMC → bajo peso · normopeso · sobrepeso · obeso · superobeso.
  categoriaImc,

  /// Cuántos factores de riesgo están presentes → alto · moderado · bajo.
  estratificacionRiesgo,
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
    this.dependeDe,
    this.visibleCuando = const [],
    this.calculo,
    this.entradasDelCalculo = const [],
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

  /// Campo del que depende para mostrarse, si depende de alguno.
  ///
  /// Es lo que el Anexo 4 escribe como «si marca SÍ, desplegar…». Un
  /// formulario que enseña de golpe todo lo que podría hacer falta obliga a
  /// leerlo entero para saber qué no aplica; enseñar solo lo que toca es el
  /// motivo por el que la doctora pidió esta revisión.
  final String? dependeDe;

  /// Valores de [dependeDe] con los que este campo aparece.
  final List<Object?> visibleCuando;

  /// Si el valor lo calcula la app en vez de teclearlo alguien.
  ///
  /// Un campo calculado se guarda igual que los demás —va al dataset como una
  /// columna más— pero no se puede editar a mano: si el IMC no cuadra, lo que
  /// hay que corregir es el peso o la talla.
  final Calculo? calculo;

  /// Claves de los campos que alimentan el cálculo, en el orden que espera.
  final List<String> entradasDelCalculo;

  bool get esCalculado => calculo != null;

  String get etiquetaConUnidad => unidad == null ? label : '$label ($unidad)';

  /// Si este campo se muestra con los valores capturados hasta ahora.
  bool visibleCon(Map<String, Object?> valores) {
    if (dependeDe == null) return true;
    return visibleCuando.contains(valores[dependeDe]);
  }

  /// `null` si el valor es aceptable; si no, el aviso a mostrar.
  String? fueraDeRango(Object? valor) {
    if (valor is! num || (min == null && max == null)) return null;
    if (min != null && valor < min!) return 'fuera de rango';
    if (max != null && valor > max!) return 'fuera de rango';
    return null;
  }
}

/// Los cálculos, en un solo sitio.
///
/// Devuelven `null` cuando les faltan datos, y eso es lo correcto: un IMC a
/// medio teclear no es un IMC de cero.
class Calculos {
  const Calculos._();

  static Object? resolver(FieldDefinition campo, Map<String, Object?> valores) {
    final entradas =
        campo.entradasDelCalculo.map((k) => valores[k]).toList();
    return switch (campo.calculo) {
      Calculo.imc => _imc(entradas),
      Calculo.categoriaImc => _categoriaImc(entradas),
      Calculo.estratificacionRiesgo => _estratificacion(entradas, valores),
      null => null,
    };
  }

  /// Peso (kg) y talla (m). Se redondea a un decimal porque es como se informa
  /// y como se compara contra los puntos de corte.
  static double? _imc(List<Object?> entradas) {
    final peso = _numero(entradas.elementAtOrNull(0));
    final talla = _numero(entradas.elementAtOrNull(1));
    if (peso == null || talla == null || talla <= 0) return null;
    return double.parse((peso / (talla * talla)).toStringAsFixed(1));
  }

  /// Los puntos de corte de la OMS, con superobesidad separada porque el Anexo
  /// 4 la usa como categoría propia.
  ///
  /// Los tramos van cerrados por abajo y abiertos por arriba —`[30, 40)`— para
  /// que ningún IMC quede sin categoría. Escritos como «30-39,9» y «>40», un
  /// IMC de 39,95 o de 40,0 exacto no entraba en ninguna casilla.
  static String? _categoriaImc(List<Object?> entradas) {
    final imc = _numero(entradas.elementAtOrNull(0));
    if (imc == null) return null;
    if (imc < 18.5) return 'Bajo peso';
    if (imc < 25) return 'Normopeso';
    if (imc < 30) return 'Sobrepeso';
    if (imc < 40) return 'Obeso';
    return 'Superobeso';
  }

  /// Cuenta los factores presentes y devuelve el nivel.
  ///
  /// Alto con 4 o más, moderado de 1 a 3, bajo con ninguno: es lo que dice el
  /// Anexo 4 y cubre los cinco factores sin dejar hueco.
  static String? _estratificacion(
      List<Object?> entradas, Map<String, Object?> valores) {
    // Sin ningún factor contestado todavía no hay estratificación: decir «bajo
    // riesgo» con el formulario en blanco sería afirmar algo que nadie ha
    // comprobado.
    final contestados = entradas.whereType<bool>().length;
    if (contestados == 0) return null;

    final presentes = entradas.where((v) => v == true).length;
    if (presentes >= 4) return 'Alto';
    if (presentes >= 1) return 'Moderado';
    return contestados == entradas.length ? 'Bajo' : null;
  }

  static double? _numero(Object? valor) => switch (valor) {
        num n => n.toDouble(),
        String s => double.tryParse(s.replaceAll(',', '.')),
        _ => null,
      };
}
