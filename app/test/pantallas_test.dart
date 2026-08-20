import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sivap/core/app_state.dart';
import 'package:sivap/core/theme/app_theme.dart';
import 'package:sivap/data/local/seed_data.dart';
import 'package:sivap/features/admin/admin_dashboard_screen.dart';
import 'package:sivap/features/auth/login_screen.dart';
import 'package:sivap/features/patients/patient_list_screen.dart';
import 'package:sivap/features/visits/visit_capture_screen.dart';

/// Pruebas de pantalla: que cada una levante y muestre lo que el diseño promete.
void main() {
  Widget montar(Widget pantalla, {AppState? estado}) {
    final state = estado ?? AppState.enMemoria();
    return AppScope(
      state: state,
      child: MaterialApp(theme: appTheme, home: pantalla),
    );
  }

  testWidgets('01 · el acceso ofrece los tres roles', (tester) async {
    await tester.pumpWidget(montar(const LoginScreen()));

    expect(find.text('SIVAP'), findsOneWidget);
    expect(find.text('Recolector de campo'), findsOneWidget);
    expect(find.text('Observador'), findsOneWidget);
    expect(find.text('Administrador'), findsOneWidget);
    // El CEI no ha aprobado: la advertencia tiene que estar a la vista.
    expect(find.textContaining('Modo demostración'), findsOneWidget);
  });

  testWidgets('02 · el recolector ve su carga y puede enrolar', (tester) async {
    final state = AppState.enMemoria()..iniciarSesion(Seed.morales);
    await tester.pumpWidget(montar(const PatientListScreen(), estado: state));

    expect(find.text('Mis pacientes'), findsOneWidget);
    expect(find.text('+ Enrolar paciente'), findsOneWidget);
    expect(find.text('Reinaldo Estévez Cruz'), findsOneWidget);
    // Paciente de otro recolector: no debe aparecer.
    expect(find.text('Idalberto Sáez Roque'), findsNothing);
  });

  testWidgets('03 · el observador ve la cohorte y no puede enrolar',
      (tester) async {
    final state = AppState.enMemoria()..iniciarSesion(Seed.betancourt);
    await tester.pumpWidget(montar(const PatientListScreen(), estado: state));

    expect(find.text('Cohorte completa'), findsOneWidget);
    expect(find.text('SOLO LECTURA'), findsOneWidget);
    expect(find.text('+ Enrolar paciente'), findsNothing);
    expect(find.text('Idalberto Sáez Roque'), findsOneWidget);
  });

  testWidgets('05 · la captura se construye desde la definición de campos',
      (tester) async {
    final state = AppState.enMemoria()..iniciarSesion(Seed.morales);
    await tester.pumpWidget(montar(
        const VisitCaptureScreen(patientId: 'p-estevez', diaInicial: 5),
        estado: state));

    // Una pestaña por día declarado, ni más ni menos.
    for (final dia in Seed.formulario.diasVisita) {
      expect(find.text('Día $dia'), findsWidgets);
    }
    // Secciones y campos vienen de la definición.
    expect(find.text('SIGNOS VITALES'), findsOneWidget);
    expect(find.textContaining('Temp. (°C)'), findsOneWidget);
    expect(find.text('Fiebre'), findsOneWidget);
  });

  testWidgets('05 · un valor fuera de rango se señala sin bloquear',
      (tester) async {
    final state = AppState.enMemoria()..iniciarSesion(Seed.morales);
    await tester.pumpWidget(montar(
        const VisitCaptureScreen(patientId: 'p-estevez', diaInicial: 5),
        estado: state));

    // La temperatura sembrada es 38.7 sobre un máximo de 37.5.
    expect(find.textContaining('fuera de rango'), findsOneWidget);
    expect(find.text('38.7'), findsOneWidget);
  });

  testWidgets('05 · una visita ya enviada no ofrece captura al recolector',
      (tester) async {
    final state = AppState.enMemoria()..iniciarSesion(Seed.morales);
    await tester.pumpWidget(montar(
        const VisitCaptureScreen(patientId: 'p-estevez', diaInicial: 1),
        estado: state));

    expect(find.text('Cerrar visita'), findsNothing);
    expect(find.textContaining('No admite cambios'), findsOneWidget);
  });

  testWidgets('07 · el panel de administración lista cohorte y auditoría',
      (tester) async {
    tester.view.physicalSize = const Size(1600, 1100);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final state = AppState.enMemoria()..iniciarSesion(Seed.guerra);
    await tester.pumpWidget(montar(const AdminDashboardScreen(), estado: state));

    expect(find.text('Pacientes de la cohorte'), findsOneWidget);
    expect(find.text('Auditoría'), findsWidgets);
    expect(find.text('Historial de auditoría — últimas correcciones'),
        findsOneWidget);
    expect(find.textContaining('error de tecleo'), findsOneWidget);
  });
}
