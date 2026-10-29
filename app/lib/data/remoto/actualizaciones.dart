import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'cliente_http_stub.dart' if (dart.library.io) 'cliente_http_io.dart';

typedef LeerVersionInstalada = Future<String> Function();
typedef AbrirDescarga = Future<bool> Function(Uri uri);

/// Únicamente avisa de APK publicadas. La instalación la confirma Android.
class Actualizaciones extends ChangeNotifier {
  Actualizaciones({
    http.Client? cliente,
    LeerVersionInstalada? leerVersionInstalada,
    AbrirDescarga? abrirDescarga,
  })  : _cliente = cliente ?? crearClienteHttp(),
        _clientePropio = cliente == null,
        _leerVersionInstalada = leerVersionInstalada ?? _versionDelPaquete,
        _abrirDescarga = abrirDescarga ?? _abrirEnNavegador;

  static final Uri _releases =
      Uri.parse('https://sivap.pages.dev/api/versiones');
  static final Uri paginaDescarga =
      Uri.parse('https://sivap.pages.dev/descargar/');

  final http.Client _cliente;
  final bool _clientePropio;
  final LeerVersionInstalada _leerVersionInstalada;
  final AbrirDescarga _abrirDescarga;

  bool consultado = false;
  bool comprobando = false;
  String? error;
  String? versionInstalada;
  String? versionDisponible;
  Future<void>? _consulta;
  bool _cerrado = false;

  bool get hayNuevaVersion => versionDisponible != null;

  Future<void> buscar({bool forzar = false}) {
    if (_consulta != null) return _consulta!;
    if (consultado && !forzar) return Future.value();
    comprobando = true;
    error = null;
    if (!_cerrado) notifyListeners();
    final consulta = _buscar();
    _consulta = consulta;
    return consulta.whenComplete(() {
      _consulta = null;
      comprobando = false;
      consultado = true;
      if (!_cerrado) notifyListeners();
    });
  }

  Future<void> _buscar() async {
    try {
      final instalada = await _leerVersionInstalada();
      final respuesta = await _cliente.get(_releases, headers: {
        'Accept': 'application/vnd.github+json',
        'User-Agent': 'SIVAP-Android',
      }).timeout(const Duration(seconds: 10));
      if (respuesta.statusCode != 200) {
        throw StateError('HTTP ${respuesta.statusCode}');
      }
      final releases = jsonDecode(respuesta.body);
      if (releases is! List) throw const FormatException('Lista de versiones');
      versionInstalada = instalada;
      versionDisponible = versionNueva(releases, instalada);
      error = null;
    } on Object {
      error = 'No se pudo comprobar la versión. Revise la conexión e inténtelo '
          'de nuevo.';
    }
  }

  /// Se aceptan versiones de prueba publicadas, pero solo si tienen APK.
  @visibleForTesting
  static String? versionNueva(List<dynamic> releases, String instalada) {
    List<int>? mayor;
    String? version;
    for (final item in releases) {
      if (item is! Map || item['draft'] == true) continue;
      final etiqueta = item['tag_name'];
      final partes = _partes(etiqueta);
      if (partes == null || _comparar(partes, _partes(instalada) ?? []) <= 0) {
        continue;
      }
      final assets = item['assets'];
      if (assets is! List ||
          !assets.any((asset) =>
              asset is Map &&
              (asset['name'] == 'sivap-${partes.join('.')}-arm64.apk' ||
                  asset['name'] ==
                      'sivap-${partes.join('.')}-universal.apk'))) {
        continue;
      }
      if (mayor == null || _comparar(partes, mayor) > 0) {
        mayor = partes;
        version = partes.join('.');
      }
    }
    return version;
  }

  static List<int>? _partes(Object? valor) {
    if (valor is! String) return null;
    final match = RegExp(r'^v?(\d+)\.(\d+)\.(\d+)$').firstMatch(valor);
    if (match == null) return null;
    return [for (var i = 1; i <= 3; i++) int.parse(match.group(i)!)];
  }

  static int _comparar(List<int> a, List<int> b) {
    if (b.length != 3) return 1;
    for (var i = 0; i < 3; i++) {
      final orden = a[i].compareTo(b[i]);
      if (orden != 0) return orden;
    }
    return 0;
  }

  Future<bool> abrirPaginaDescarga() => _abrirDescarga(paginaDescarga);

  static Future<String> _versionDelPaquete() async =>
      (await PackageInfo.fromPlatform()).version;

  static Future<bool> _abrirEnNavegador(Uri uri) =>
      launchUrl(uri, mode: LaunchMode.externalApplication);

  @override
  void dispose() {
    _cerrado = true;
    if (_clientePropio) _cliente.close();
    super.dispose();
  }
}
