import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

void descargarArchivo(String nombre, List<int> bytes, String tipo) {
  final contenido = Uint8List.fromList(bytes).toJS;
  final objeto = web.Blob([contenido].toJS, web.BlobPropertyBag(type: tipo));
  final url = web.URL.createObjectURL(objeto);
  try {
    final enlace = web.document.createElement('a') as web.HTMLAnchorElement;
    enlace.href = url;
    enlace.download = nombre;
    enlace.click();
  } finally {
    // El navegador necesita conservar la URL hasta que empiece la descarga.
    Future<void>.delayed(
        const Duration(seconds: 5), () => web.URL.revokeObjectURL(url));
  }
}
