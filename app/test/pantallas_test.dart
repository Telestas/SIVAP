import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sivap/core/app_state.dart';
import 'package:sivap/core/theme/app_theme.dart';
import 'package:sivap/data/local/seed_data.dart';
import 'package:sivap/domain/models/evento_clinico.dart';
import 'package:sivap/features/admin/admin_dashboard_screen.dart';
import 'package:sivap/features/auth/login_screen.dart';
import 'package:sivap/features/eventos/evento_form_screen.dart';
import 'package:sivap/features/eventos/paciente_timeline_screen.dart';
import 'package:sivap/features/patients/patient_list_screen.dart';

/// Pruebas de pantalla: que cada una levante y muestre lo que promete.
void main() {
  Widget montar(Widget pantalla, {AppState? estado}) {
    final state = estado ?? AppState.enMemoria();
    return AppScope(
      state: state,
      child: MaterialApp(theme: appTheme, home: pantalla),
    );
  }

  /// Fija el tamaño de pantalla de la prueba.
  ///
  /// El lienzo por defecto de `flutter_test` es 800x600. Las pantallas son
  /// listas: lo que cae por debajo de esa altura ni siquiera se construye, y
  /// `find.text` no lo encuentra aunque el código sea correcto.
  void lienzo(WidgetTester tester, {double ancho = 420, double alto = 2400}) {
    tester.view.physicalSize = Size(ancho, alto);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  testWidgets('el acceso ofrece los tres roles', (tester) async {
    lienzo(tester);
    await tester.pumpWidget(montar(const LoginScreen()));

    expect(find.text('SIVAP'), findsOneWidget);
    expect(find.text('Recolector de campo'), findsOneWidget);
    expect(find.text('Observador'), findsOneWidget);
    expect(find.text('Administrador'), findsOneWidget);
    // El CEI no ha aprobado: la advertencia tiene que estar a la vista.
    expect(find.textContaining('Modo demostración'), findsOneWidget);
  });

  testWidgets('el recolector ve su carga y puede enrolar', (tester) async {
    lienzo(tester);
    final state = AppState.enMemoria()..iniciarSesion(Seed.morales);
    await tester.pumpWidget(montar(const PatientListScreen(), estado: state));

    expect(find.text('Mis pacientes'), findsOneWidget);
    expect(find.text('+ Enrolar paciente'), findsOneWidget);
    expect(find.text('Reinaldo Estévez Cruz'), findsOneWidget);
    // Paciente de otro recolector: no debe aparecer.
    expect(find.text('Idalberto Sáez Roque'), findsNothing);
  });

  testWidgets('el observador ve la cohorte y no puede enrolar', (tester) async {
    lienzo(tester);
    final state = AppState.enMemoria()..iniciarSesion(Seed.betancourt);
    await tester.pumpWidget(montar(const PatientListScreen(), estado: state));

    expect(find.text('Cohorte completa'), findsOneWidget);
    expect(find.text('SOLO LECTURA'), findsOneWidget);
    expect(find.text('+ Enrolar paciente'), findsNothing);
    expect(find.text('Idalberto Sáez Roque'), findsOneWidget);
    // Los recuentos van en A/B, sin decir cuál es cuál.
    expect(find.text('PROTOCOLO A'), findsOneWidget);
    expect(find.text('PROTOCOLO B'), findsOneWidget);
  });

  testWidgets('la línea de tiempo muestra las fases y los hitos',
      (tester) async {
    lienzo(tester, alto: 4000);
    final state = AppState.enMemoria()..iniciarSesion(Seed.morales);
    await tester.pumpWidget(montar(
        const PacienteTimelineScreen(patientId: 'p-demo-01'),
        estado: state));

    expect(find.text('FASE 2 · CRIBADO'), findsOneWidget);
    expect(find.text('Prueba de ventilación espontánea'), findsWidgets);
    // Hito repetible: se anuncia como tal.
    expect(find.text('REPETIBLE'), findsWidgets);
  });

  testWidgets('un hito repetible lista todas sus ocurrencias', (tester) async {
    lienzo(tester, alto: 4000);
    final state = AppState.enMemoria()..iniciarSesion(Seed.morales);
    await tester.pumpWidget(montar(
        const PacienteTimelineScreen(patientId: 'p-demo-01'),
        estado: state));

    // Tres cribados y dos intentos de PVE: exactamente lo que el modelo de
    // calendario no podía representar.
    // Cribado tiene tres ocurrencias y la evaluación diaria una: «Día 1»
    // aparece en ambas, «Día 3» solo en el cribado.
    expect(find.textContaining('Día 1 ·'), findsWidgets);
    expect(find.textContaining('Día 3 ·'), findsOneWidget);
    expect(find.textContaining('Intento 1 ·'), findsOneWidget);
    expect(find.textContaining('Intento 2 ·'), findsOneWidget);
  });

  testWidgets('el formulario se construye desde la definición del evento',
      (tester) async {
    lienzo(tester, alto: 3000);
    final state = AppState.enMemoria()..iniciarSesion(Seed.morales);
    await tester.pumpWidget(montar(
      const EventoFormScreen.nuevo(
        patientId: 'p-demo-01',
        tipo: TipoEvento.pruebaVentilacionEspontanea,
      ),
      estado: state,
    ));

    expect(find.text('MONITORIZACIÓN AL INICIO'), findsOneWidget);
    expect(find.text('MONITORIZACIÓN AL FINAL'), findsOneWidget);
    expect(find.text('Tubo en T'), findsOneWidget);
    expect(find.text('FECHA EN QUE OCURRIÓ'), findsOneWidget);
  });

  testWidgets('un evento registrado no ofrece captura al recolector',
      (tester) async {
    lienzo(tester, alto: 3000);
    final state = AppState.enMemoria()..iniciarSesion(Seed.morales);
    final evento = state.repo
        .eventosDe('p-demo-03')
        .firstWhere((e) => e.tipo == TipoEvento.extubacion);

    await tester.pumpWidget(montar(
      EventoFormScreen.existente(
        patientId: 'p-demo-03',
        tipo: TipoEvento.extubacion,
        eventoId: evento.id,
      ),
      estado: state,
    ));

    expect(find.text('Registrar'), findsNothing);
    expect(find.textContaining('No admite cambios'), findsOneWidget);
  });

  testWidgets('el panel de administración lista cohorte y auditoría',
      (tester) async {
    lienzo(tester, ancho: 1600, alto: 1600);
    final state = AppState.enMemoria()..iniciarSesion(Seed.guerra);
    await tester.pumpWidget(montar(const AdminDashboardScreen(), estado: state));

    expect(find.text('Pacientes del ensayo'), findsOneWidget);
    expect(find.text('AVANCE POR FASES'), findsOneWidget);
    expect(find.text('Historial de auditoría — últimas correcciones'),
        findsOneWidget);
    expect(find.textContaining('cifras transpuestas'), findsOneWidget);
    // El recuento por rama no dice cuál es cuál.
    expect(find.textContaining('A: '), findsOneWidget);
  });
}
