import 'package:flutter_test/flutter_test.dart';
import 'package:sivap/domain/models/validacion_ficha.dart';

void main() {
  test('la ficha rechaza errores de escritura y conserva formatos reales', () {
    expect(ValidacionFicha.nombre('Paciente 123'), isNotNull);
    expect(ValidacionFicha.nombre('!!!'), isNotNull);
    expect(ValidacionFicha.nombre('María del Carmen'), isNull);
    expect(ValidacionFicha.historia('HC-24/001'), isNull);
    expect(ValidacionFicha.historia('HC-1\nOTRA'), isNotNull);
    expect(ValidacionFicha.edad('-3'), isNotNull);
    expect(ValidacionFicha.edad('999'), isNotNull);
    expect(ValidacionFicha.edad('118'), isNull);
    expect(ValidacionFicha.telefono('abc123'), isNotNull);
    expect(ValidacionFicha.telefono('+53 5555 1234'), isNull);
    expect(ValidacionFicha.telefono('', opcional: true), isNull);
  });
}
