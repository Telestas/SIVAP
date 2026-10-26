/// Comprobaciones de escritura de la ficha identificable.
///
/// Los datos clínicos extraordinarios se revisan, no se descartan por una
/// regla estadística. Aquí se rechazan campos vacíos, formatos imposibles y
/// edades que no pueden expresarse razonablemente en años cumplidos.
class ValidacionFicha {
  const ValidacionFicha._();

  static String? nombre(String valor) {
    final texto = valor.trim();
    if (texto.isEmpty) return 'Escriba el nombre y los apellidos.';
    if (texto.length < 2 || texto.length > 120) {
      return 'Use entre 2 y 120 caracteres.';
    }
    if (!RegExp(r"^[\p{L}]+(?:[ '\-][\p{L}]+)*$", unicode: true)
        .hasMatch(texto)) {
      return 'Use letras y separadores de nombre; revise cifras o símbolos.';
    }
    return null;
  }

  static String? historia(String valor) {
    final texto = valor.trim();
    if (texto.isEmpty) return 'Escriba el número de historia clínica.';
    if (texto.length > 64 ||
        RegExp(r'[\x00-\x1f]').hasMatch(texto) ||
        !RegExp(r'[\p{L}\p{N}]', unicode: true).hasMatch(texto)) {
      return 'Revise el número de historia clínica (máximo 64 caracteres).';
    }
    return null;
  }

  static String? edad(String valor) {
    final texto = valor.trim();
    if (texto.isEmpty) return 'Escriba la edad en años cumplidos.';
    if (!RegExp(r'^\d{1,3}$').hasMatch(texto)) {
      return 'Escriba solo años completos, sin signos ni decimales.';
    }
    final numero = int.parse(texto);
    if (numero > 130) return 'Revise la edad: supera 130 años.';
    return null;
  }

  static String? telefono(String valor, {bool opcional = false}) {
    final texto = valor.trim();
    if (texto.isEmpty) {
      return opcional ? null : 'Escriba un teléfono de contacto.';
    }
    if (!RegExp(r'^\+?[0-9\s().-]+$').hasMatch(texto)) {
      return 'Use solo cifras, espacios, +, guiones o paréntesis.';
    }
    final cifras = texto.replaceAll(RegExp(r'\D'), '');
    if (cifras.length < 6 || cifras.length > 15) {
      return 'El teléfono debe tener entre 6 y 15 cifras.';
    }
    return null;
  }
}
