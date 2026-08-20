import 'package:flutter/material.dart';

import 'core/app_state.dart';
import 'core/theme/app_theme.dart';
import 'domain/models/role.dart';
import 'features/admin/admin_dashboard_screen.dart';
import 'features/auth/login_screen.dart';
import 'features/patients/patient_list_screen.dart';

void main() => runApp(const SivapApp());

class SivapApp extends StatefulWidget {
  const SivapApp({super.key});

  @override
  State<SivapApp> createState() => _SivapAppState();
}

class _SivapAppState extends State<SivapApp> {
  final _state = AppState();

  @override
  void dispose() {
    _state.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AppScope(
        state: _state,
        child: MaterialApp(
          title: 'SIVAP',
          debugShowCheckedModeBanner: false,
          theme: appTheme,
          home: const _Raiz(),
        ),
      );
}

/// Decide qué pantalla corresponde: sin sesión, acceso; con sesión, la lista de
/// campo o el panel de administración.
class _Raiz extends StatelessWidget {
  const _Raiz();

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    if (state.usuario == null) return const LoginScreen();

    // El administrador trabaja en escritorio (maqueta 07); en pantalla estrecha
    // recibe la misma lista que el resto para no dejarlo sin app en el móvil.
    final ancha = MediaQuery.sizeOf(context).width >= 900;
    return state.usuarioActual.role == Role.administrador && ancha
        ? const AdminDashboardScreen()
        : const PatientListScreen();
  }
}
