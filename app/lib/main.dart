import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'app.dart';
import 'core/app_state.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/tokens.dart';
import 'core/widgets/controls.dart';
import 'data/local/abrir_almacen.dart';
import 'data/local/almacen_local.dart';

/// Modo de almacén con el que arranca esta compilación.
///
/// Demostración y producción usan archivos de base de datos distintos, así que
/// cambiar esta constante nunca mezcla datos inventados con datos reales.
/// Pasará a `produccion` cuando el CEI apruebe el estudio.
const ModoAlmacen modoAlmacen = ModoAlmacen.demostracion;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SivapApp());
}

class SivapApp extends StatefulWidget {
  const SivapApp({super.key});

  @override
  State<SivapApp> createState() => _SivapAppState();
}

class _SivapAppState extends State<SivapApp> {
  late final Future<AppState> _arranque = _abrir();
  AppState? _state;

  Future<AppState> _abrir() async {
    final almacen = await abrirAlmacen(modoAlmacen);
    return _state = AppState(almacen);
  }

  @override
  void dispose() {
    _state?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<AppState>(
        future: _arranque,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _sinEstado(_FalloDeArranque(error: snapshot.error!));
          }
          if (!snapshot.hasData) return _sinEstado(const _Abriendo());
          return raizDeLaApp(snapshot.data!);
        },
      );

  /// Mientras la base se abre —o si no se pudo abrir— no hay estado que
  /// ofrecer, así que estas dos pantallas van sin ámbito. Ninguna lo usa.
  Widget _sinEstado(Widget pantalla) => MaterialApp(
        title: 'SIVAP',
        debugShowCheckedModeBanner: false,
        theme: appTheme,
        locale: const Locale('es'),
        supportedLocales: const [Locale('es')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: pantalla,
      );
}

class _Abriendo extends StatelessWidget {
  const _Abriendo();

  @override
  Widget build(BuildContext context) => const Scaffold(
        backgroundColor: T.surface,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('SIVAP',
                  style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                      color: T.ink)),
              SizedBox(height: 14),
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: T.accent),
              ),
            ],
          ),
        ),
      );
}

/// La app no pudo abrir su almacén. No entra igualmente.
///
/// El caso que más importa es `CifradoNoDisponible`: seguir adelante
/// significaría escribir nombres y datos clínicos en claro. Es preferible una
/// app que no arranca a una que guarda eso sin cifrar.
class _FalloDeArranque extends StatelessWidget {
  const _FalloDeArranque({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: T.surface,
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SectionLabel('No se pudo abrir el almacén local'),
                  const SizedBox(height: 10),
                  const Text(
                      'La app no arranca porque no puede guardar los datos con '
                      'las garantías que exige el estudio.',
                      style: TextStyle(fontSize: 15, color: T.ink, height: 1.5)),
                  const SizedBox(height: 16),
                  StatusBanner(texto: error.toString(), alineaArriba: true),
                ],
              ),
            ),
          ),
        ),
      );
}
