import 'package:http/http.dart' as http;

String? diagnosticoConexion(Object error) => error is http.ClientException
    ? 'No se pudo conectar con sivap.pages.dev. Compruebe la conexión.'
    : null;

Future<String> diagnosticarConexionMovil() async =>
    'El diagnóstico está disponible en Android.';
