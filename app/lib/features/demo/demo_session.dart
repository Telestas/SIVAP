import 'package:flutter/material.dart';

import '../../app.dart';
import '../../core/app_state.dart';
import '../../core/theme/tokens.dart';
import '../../data/local/seed_data.dart';

/// Sesión aislada para recorrer el flujo sin Firebase ni datos del estudio.
class DemoSession extends StatefulWidget {
  const DemoSession({super.key});

  @override
  State<DemoSession> createState() => _DemoSessionState();
}

class _DemoSessionState extends State<DemoSession> {
  late final AppState _estado = AppState.demostracion()
    ..iniciarSesion(Seed.principal);

  @override
  void dispose() {
    _estado.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
        children: [
          Material(
            color: T.accentTint,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'MODO PRUEBA · solo datos ficticios',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Salir de prueba'),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(child: raizDeLaApp(_estado)),
        ],
      );
}
