/// Selección del almacén por plataforma.
///
/// Móvil y escritorio abren la base cifrada; el navegador no puede, y arranca
/// en memoria avisando de ello. La importación condicional es lo que evita que
/// el código de SQLCipher —que no compila para web— entre en el build web.
library;

export 'abrir_almacen_io.dart'
    if (dart.library.js_interop) 'abrir_almacen_web.dart';
