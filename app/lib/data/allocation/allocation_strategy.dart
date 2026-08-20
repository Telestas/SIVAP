import '../../domain/models/protocolo.dart';

/// Generador pseudoaleatorio **splitmix32**, escrito aquí a propósito.
///
/// No se usa `Random(semilla)` del SDK: Dart no garantiza que su generador sea
/// el mismo entre versiones, y una secuencia de aleatorización que deja de ser
/// reproducible cuando se actualiza el SDK no es auditable. Fijando el
/// algoritmo en nuestro propio código, la secuencia depende solo de la semilla
/// y de estas veinte líneas.
///
/// El algoritmo, para quien quiera reimplementarlo y verificar (cualquier
/// lenguaje sirve; toda la aritmética es sobre enteros de 32 bits sin signo):
///
/// ```
/// estado = (estado + 0x9E3779B9) mod 2^32
/// z = estado
/// z = ((z XOR (z >>> 16)) * 0x21F0AAAD) mod 2^32
/// z = ((z XOR (z >>> 15)) * 0x735A2D97) mod 2^32
/// z = z XOR (z >>> 15)
/// bit = z AND 1        // 1 = Protocolo B, 0 = Protocolo A
/// ```
///
/// Vectores de verificación (los comprueba `test/restricciones_test.dart`):
///
/// - semilla 12345, 16 bits → `1101101100000100`
/// - semilla 987, 32 bits   → `10111100101110101111001101000111`
class SplitMix32 {
  SplitMix32(int semilla) : _estado = semilla & _mascara;

  static const int _mascara = 0xFFFFFFFF;
  int _estado;

  /// Siguiente valor de 32 bits de la secuencia.
  int siguiente() {
    _estado = (_estado + 0x9E3779B9) & _mascara;
    var z = _estado;
    z = ((z ^ (z >>> 16)) * 0x21F0AAAD) & _mascara;
    z = ((z ^ (z >>> 15)) * 0x735A2D97) & _mascara;
    return z ^ (z >>> 15);
  }

  /// Siguiente bit: el sorteo de una asignación.
  bool siguienteBit() => siguiente().isOdd;
}

/// Secuencia de asignación: la lista de ramas que se consumirá en orden, más
/// su procedencia.
///
/// La procedencia es tan importante como la lista. Una asignación aleatoria que
/// nadie puede reproducir no es auditable, y un estudio cuya aleatorización no
/// se puede auditar es un estudio impugnable.
class AllocationSequence {
  const AllocationSequence({
    required this.valores,
    required this.etiqueta,
    required this.origen,
    required this.generadaEn,
    this.semilla,
  });

  /// Secuencia generada por computadora a partir de [semilla], con [SplitMix32].
  ///
  /// Aleatorización simple: cada posición se sortea de forma independiente, sin
  /// bloques ni estratos. Es lo que el equipo decidió (BASES §6).
  ///
  /// La semilla queda guardada: con ella se regenera exactamente esta misma
  /// secuencia en cualquier momento —en esta app, o reimplementando el
  /// algoritmo en Python o R desde la especificación de [SplitMix32]— lo que
  /// permite verificar a posteriori que las asignaciones registradas son las
  /// que la secuencia dictaba.
  factory AllocationSequence.generada({
    required int semilla,
    required int longitud,
    required DateTime ahora,
    String? etiqueta,
  }) {
    final azar = SplitMix32(semilla);
    return AllocationSequence(
      valores: List.unmodifiable(List.generate(
          longitud, (_) => azar.siguienteBit() ? Protocolo.b : Protocolo.a)),
      etiqueta: etiqueta ?? 'semilla $semilla',
      origen: OrigenSecuencia.generadaPorComputadora,
      generadaEn: ahora,
      semilla: semilla,
    );
  }

  /// Secuencia entregada desde fuera (por ejemplo, por un bioestadista).
  /// No lleva semilla: su trazabilidad es el documento que la acompaña.
  factory AllocationSequence.cargada({
    required List<Protocolo> valores,
    required String etiqueta,
    required DateTime ahora,
  }) =>
      AllocationSequence(
        valores: List.unmodifiable(valores),
        etiqueta: etiqueta,
        origen: OrigenSecuencia.cargada,
        generadaEn: ahora,
      );

  final List<Protocolo> valores;
  final String etiqueta;
  final OrigenSecuencia origen;
  final DateTime generadaEn;

  /// Presente solo si la secuencia se generó por computadora.
  final int? semilla;

  int get longitud => valores.length;

  /// La secuencia como código binario: `0` = Protocolo A, `1` = Protocolo B.
  /// Es la forma compacta de dejarla en el acta del estudio y de compararla
  /// contra lo efectivamente asignado.
  ///
  /// Qué protocolo terapéutico hay detrás de A y de B no está aquí ni en
  /// ninguna otra parte del sistema (CLAUDE.md §2).
  String get codigoBinario =>
      valores.map((p) => p == Protocolo.b ? '1' : '0').join();

  /// Cuántas de cada rama. En aleatorización simple el reparto NO queda
  /// equilibrado por construcción: con 60 pacientes es normal terminar 33/27.
  /// Si el desequilibrio importa, la decisión es pasar a bloques, y eso es
  /// otra implementación de [AllocationStrategy], no un parche aquí.
  ({int a, int b}) get reparto => (
        a: valores.where((p) => p == Protocolo.a).length,
        b: valores.where((p) => p == Protocolo.b).length,
      );

  /// Regenera la secuencia desde su semilla y comprueba que coincide.
  /// Es la verificación que puede correr un auditor externo.
  bool verificaContraSemilla() {
    final s = semilla;
    if (s == null) return false;
    return AllocationSequence.generada(
          semilla: s,
          longitud: longitud,
          ahora: generadaEn,
        ).codigoBinario ==
        codigoBinario;
  }
}

enum OrigenSecuencia {
  generadaPorComputadora('generada por computadora'),
  cargada('cargada desde lista externa');

  const OrigenSecuencia(this.descripcion);
  final String descripcion;
}

/// Resultado de asignar una rama a un paciente elegible.
class Allocation {
  const Allocation({
    required this.protocolo,
    required this.etiquetaSecuencia,
    required this.asignadoEn,
    required this.posicion,
  });

  final Protocolo protocolo;

  /// Identificador de la secuencia de la que salió esta asignación.
  final String etiquetaSecuencia;
  final DateTime asignadoEn;

  /// Posición ocupada dentro de la secuencia (1 = primera). Junto con la
  /// semilla, permite recalcular esta asignación concreta desde cero.
  final int posicion;
}

/// Módulo de asignación de protocolo.
///
/// Restricción no negociable (CLAUDE.md §4): esta pieza está aislada y es
/// reemplazable. Si más adelante se decide aleatorización por bloques o
/// estratificada, se implementa otra clase con esta misma interfaz y no se
/// toca nada más de la app.
///
/// Lo que NUNCA debe existir: una implementación que reciba el protocolo
/// elegido por el investigador. Eso es sesgo de selección e invalida el estudio.
abstract class AllocationStrategy {
  /// Descripción legible del método, para mostrar en pantalla y exportar junto
  /// al dataset.
  String get descripcion;

  /// Consume la siguiente entrada de la secuencia. Lanza [AllocationExhausted]
  /// si se agotó — enrolar más allá de la secuencia prevista es un error del
  /// estudio, no algo que la app deba improvisar sobre la marcha.
  Allocation asignar({required DateTime ahora});

  /// Cuántas asignaciones quedan disponibles.
  int get restantes;
}

class AllocationExhausted implements Exception {
  const AllocationExhausted(this.consumidas);

  final int consumidas;

  @override
  String toString() =>
      'Secuencia de aleatorización agotada tras $consumidas asignaciones. '
      'Genere una secuencia nueva antes de seguir enrolando.';
}

/// Implementación por defecto del MVP: **aleatorización simple**, con la
/// secuencia generada íntegra ANTES de empezar a enrolar y consumida en orden.
///
/// El punto no es de dónde salen los números, sino cuándo: la secuencia existe
/// completa antes del primer paciente. Sortear en el momento de enrolar dejaría
/// la puerta abierta a repetir el sorteo hasta que salga la rama que se
/// prefiere, y eso no deja rastro.
class SequentialAllocation implements AllocationStrategy {
  SequentialAllocation({required this.secuencia, int consumidas = 0})
      : _cursor = consumidas;

  final AllocationSequence secuencia;
  int _cursor;

  @override
  String get descripcion =>
      'Aleatorización simple · secuencia ${secuencia.origen.descripcion} '
      '· ${secuencia.etiqueta}';

  @override
  int get restantes => secuencia.longitud - _cursor;

  int get consumidas => _cursor;

  @override
  Allocation asignar({required DateTime ahora}) {
    if (_cursor >= secuencia.longitud) throw AllocationExhausted(_cursor);
    final protocolo = secuencia.valores[_cursor];
    _cursor++;
    return Allocation(
      protocolo: protocolo,
      etiquetaSecuencia: secuencia.etiqueta,
      asignadoEn: ahora,
      posicion: _cursor,
    );
  }

  // No existe forma de consultar la siguiente rama sin consumirla, y es
  // deliberado. Saber qué rama toca antes de decidir a quién se enrola es
  // exactamente el sesgo de selección que la aleatorización existe para
  // evitar. Si alguna pantalla llega a "necesitar" esa consulta, el problema
  // está en la pantalla.
}
