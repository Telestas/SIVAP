import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/app_state.dart';
import 'core/theme/app_theme.dart';
import 'features/admin/admin_dashboard_screen.dart';
import 'features/auth/login_screen.dart';
import 'features/patients/patient_list_screen.dart';

/// Árbol de la aplicación.
///
/// **`AppScope` va por encima de `MaterialApp`, no dentro de su `home`.** El
/// `Navigator` lo crea `MaterialApp`, así que todo lo que se abra con `push` se
/// construye por encima de `home`: con el ámbito ahí dentro, cualquier pantalla
/// empujada —enrolar, consentimiento, línea de tiempo— se quedaba sin él y
/// fallaba al arrancar, dejando la pantalla en blanco.
///
/// Esta función existe para que las pruebas monten **este** árbol y no uno
/// parecido. Armarlo a mano en cada prueba fue justamente lo que dejó pasar ese
/// fallo: las pruebas ponían el ámbito en su sitio y la app no.
Widget raizDeLaApp(AppState estado, {Widget inicio = const Raiz()}) => AppScope(
      state: estado,
      child: MaterialApp(
        title: 'SIVAP',
        debugShowCheckedModeBanner: false,
        theme: appTheme,
        // Toda la interfaz en español, incluidos los diálogos que pone Flutter.
        locale: const Locale('es'),
        supportedLocales: const [Locale('es')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: inicio,
      ),
    );

/// Decide qué pantalla corresponde: sin sesión, acceso; con sesión, la lista de
/// campo o el panel de administración.
class Raiz extends StatelessWidget {
  const Raiz({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    if (state.usuario == null) return const LoginScreen();

    // Quien administra o analiza trabaja en escritorio; en pantalla estrecha
    // recibe la misma lista que el resto, para no dejarlo sin app en el móvil.
    final usuario = state.usuarioActual;
    final ancha = MediaQuery.sizeOf(context).width >= 900;
    final panel = usuario.puedeGestionarUsuarios || usuario.puedeExportar;
    return panel && ancha
        ? const AdminDashboardScreen()
        : const PatientListScreen();
  }
}
