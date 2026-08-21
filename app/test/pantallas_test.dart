import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sivap/app.dart';
import 'package:sivap/core/app_state.dart';
import 'package:sivap/data/local/seed_data.dart';
import 'package:sivap/domain/models/evento_clinico.dart';
import 'package:sivap/features/admin/admin_dashboard_screen.dart';
import 'package:sivap/features/auth/login_screen.dart';
import 'package:sivap/domain/models/role.dart';
import 'package:sivap/features/enrollment/enrollment_screen.dart';
import 'package:sivap/features/eventos/evento_form_screen.dart';
import 'package:sivap/features/eventos/paciente_timeline_screen.dart';
import 'package:sivap/features/patients/patient_list_screen.dart';

/// Pruebas de pantalla: que cada una levante y muestre lo que promete.
void main() {
  /// Monta **el árbol real de la app**, no uno parecido.
  ///
  /// Antes cada prueba lo armaba a mano, con `AppScope` por encima de
  /// `MaterialApp`. La app lo tenía dentro de `home`, así que toda pantalla
  /// abierta con `push` se quedaba sin ámbito y salía en blanco — y las
  /// pruebas no lo veían porque probaban otro árbol.
  Widget montar(Widget pantalla, {AppState? estado}) =>
      raizDeLaApp(estado ?? AppState.enMemoria(), inicio: pantalla);

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

  testWidgets('navegar a una pantalla nueva no la deja en blanco',
      (tester) async {
    // La regresión que se coló hasta el teléfono: `AppScope` estaba dentro de
    // `MaterialApp.home`, el `Navigator` quedaba por encima, y cualquier
    // pantalla empujada se construía fuera del ámbito.
    lienzo(tester, alto: 2400);
    final state = AppState.enMemoria()..iniciarSesion(Seed.reclutador);
    await tester.pumpWidget(montar(const PatientListScreen(), estado: state));

    await tester.tap(find.text('+ Enrolar paciente'));
    await tester.pumpAndSettle();

    expect(find.text('Enrolar paciente'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('el enrolamiento pide centro y solo la ficha mínima',
      (tester) async {
    lienzo(tester, alto: 2600);
    final state = AppState.enMemoria()..iniciarSesion(Seed.reclutador);
    await tester.pumpWidget(montar(const EnrollmentScreen(), estado: state));

    expect(find.text('CENTRO'), findsOneWidget);
    expect(find.text('Hospital clínico-quirúrgico docente'), findsOneWidget);
    expect(find.text('NOMBRE Y APELLIDOS'), findsOneWidget);
    // Retirados por minimización de datos personales (CLAUDE.md §9).
    expect(find.textContaining('CARNÉ'), findsNothing);
    expect(find.textContaining('DIRECCIÓN'), findsNothing);
  });

  testWidgets('el usuario se puede escribir y selecciona su función',
      (tester) async {
    lienzo(tester);
    await tester.pumpWidget(montar(const LoginScreen()));

    await tester.enterText(
        find.widgetWithText(TextField, 'Ej.: investigador.uno'),
        Seed.evaluador.usuario);
    await tester.pump();

    // Teclear un usuario selecciona su función: los dos controles miran lo
    // mismo.
    expect(find.text('Cegado a: ${Rol.evaluadorDesenlaces.cegadoA}'),
        findsOneWidget);
  });

  testWidgets('la contraseña se oculta y el ojo la muestra', (tester) async {
    lienzo(tester);
    await tester.pumpWidget(montar(const LoginScreen()));

    final campo = find.byType(TextField).at(1);
    expect(tester.widget<TextField>(campo).obscureText, isTrue);

    await tester.tap(find.byIcon(Icons.visibility_outlined));
    await tester.pump();

    expect(tester.widget<TextField>(campo).obscureText, isFalse);
  });

  testWidgets('un usuario que no existe no entra, y lo dice', (tester) async {
    lienzo(tester);
    final state = AppState.enMemoria();
    await tester.pumpWidget(montar(const LoginScreen(), estado: state));

    await tester.enterText(
        find.widgetWithText(TextField, 'Ej.: investigador.uno'), 'nadie');
    await tester.enterText(find.byType(TextField).at(1), 'algo');
    await tester.tap(find.text('Entrar'));
    await tester.pump();

    expect(find.textContaining('No hay ningún investigador'), findsOneWidget);
    expect(state.usuario, isNull);
  });

  testWidgets('el acceso ofrece los tres roles', (tester) async {
    lienzo(tester);
    await tester.pumpWidget(montar(const LoginScreen()));

    expect(find.text('SIVAP'), findsOneWidget);
    // Una opción por función del ensayo.
    expect(find.text('Aplicador'), findsOneWidget);
    expect(find.text('Evaluador de desenlaces'), findsOneWidget);
    expect(find.text('Investigador principal'), findsOneWidget);
    expect(find.text('Observador'), findsOneWidget);
    // El CEI no ha aprobado: la advertencia tiene que estar a la vista.
    expect(find.textContaining('Modo demostración'), findsOneWidget);
  });

  testWidgets('el recolector ve su carga y puede enrolar', (tester) async {
    lienzo(tester);
    final state = AppState.enMemoria()..iniciarSesion(Seed.reclutador);
    await tester.pumpWidget(montar(const PatientListScreen(), estado: state));

    expect(find.text('Mis pacientes'), findsOneWidget);
    expect(find.text('+ Enrolar paciente'), findsOneWidget);
    expect(find.textContaining('HC-001'), findsOneWidget);
    // Paciente de otro centro y otro recolector: no debe aparecer.
    expect(find.textContaining('IC-001'), findsNothing);
  });

  testWidgets('el observador ve la cohorte y no puede enrolar', (tester) async {
    lienzo(tester);
    final state = AppState.enMemoria()..iniciarSesion(Seed.observador);
    await tester.pumpWidget(montar(const PatientListScreen(), estado: state));

    expect(find.text('Cohorte completa'), findsOneWidget);
    expect(find.text('SOLO LECTURA'), findsOneWidget);
    expect(find.text('+ Enrolar paciente'), findsNothing);
    expect(find.text('IC-001'), findsOneWidget);
    // Los recuentos van en A/B, sin decir cuál es cuál.
    expect(find.text('PROTOCOLO A'), findsOneWidget);
    expect(find.text('PROTOCOLO B'), findsOneWidget);
  });

  testWidgets('la línea de tiempo muestra las fases y los hitos',
      (tester) async {
    lienzo(tester, alto: 4000);
    final state = AppState.enMemoria()..iniciarSesion(Seed.reclutador);
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
    final state = AppState.enMemoria()..iniciarSesion(Seed.reclutador);
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
    final state = AppState.enMemoria()..iniciarSesion(Seed.reclutador);
    await tester.pumpWidget(montar(
      const EventoFormScreen.nuevo(
        patientId: 'p-demo-01',
        tipo: TipoEvento.pruebaVentilacionEspontanea,
      ),
      estado: state,
    ));

    expect(find.text('MONITORIZACIÓN AL INICIO DE LA PVE'), findsOneWidget);
    expect(find.text('MONITORIZACIÓN AL FINAL DE LA PVE'), findsOneWidget);
    expect(find.text('Tubo en T'), findsOneWidget);
    expect(find.text('FECHA EN QUE OCURRIÓ'), findsOneWidget);
  });

  testWidgets('un evento registrado no ofrece captura al recolector',
      (tester) async {
    lienzo(tester, alto: 3000);
    final state = AppState.enMemoria()..iniciarSesion(Seed.reclutador);
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
    final state = AppState.enMemoria()..iniciarSesion(Seed.principal);
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
