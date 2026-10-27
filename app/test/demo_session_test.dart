import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sivap/app.dart';
import 'package:sivap/core/app_state.dart';
import 'package:sivap/core/widgets/controls.dart';
import 'package:sivap/data/local/almacen_local.dart';
import 'package:sivap/data/local/in_memory_study_repository.dart';
import 'package:sivap/data/local/seed_data.dart';
import 'package:sivap/data/remoto/cola_de_envio.dart';
import 'package:sivap/features/consent/consent_screen.dart';

void main() {
  testWidgets(
      'la prueba offline recorre ficha y consentimiento sin sesión real',
      (tester) async {
    tester.view.physicalSize = const Size(360, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final repoReal = InMemoryStudyRepository();
    final sesionReal = AppState(
      AlmacenLocal(
        repo: repoReal,
        persistente: true,
        cifrado: true,
        descripcion: 'Prueba de acceso remoto',
      ),
      autenticarUsuario: (_, __) async => Seed.principal,
      cargarRepositorioRemoto: (_) async => repoReal,
    );
    addTearDown(sesionReal.dispose);
    await tester.pumpWidget(raizDeLaApp(sesionReal));

    await tester.tap(find.text('Probar flujo sin conexión'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.textContaining('MODO PRUEBA'), findsOneWidget);
    expect(sesionReal.usuario, isNull);

    await tester.tap(find.text('+ Enrolar paciente'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Ninguno está presente'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    Future<void> rellenar(String etiqueta, String valor) async {
      final campo = find.descendant(
        of: find.byWidgetPredicate(
            (widget) => widget is LabeledField && widget.label == etiqueta),
        matching: find.byType(TextField),
      );
      await tester.enterText(campo, valor);
    }

    await rellenar('Nombre y apellidos', 'Paciente Ficticio');
    await rellenar('Núm. de historia clínica', 'PRUEBA-001');
    await rellenar('Edad', '60');
    await rellenar('Teléfono de contacto', '55512345');
    await tester.pump();

    expect(
      tester
          .widget<AppButton>(find.widgetWithText(AppButton, 'Guardar'))
          .enabled,
      isTrue,
    );
    expect(
      tester
          .widget<AppButton>(
              find.widgetWithText(AppButton, 'Ir a consentimiento'))
          .enabled,
      isTrue,
    );
    await tester.tap(find.text('Ir a consentimiento'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(ConsentScreen), findsOneWidget);
    expect(find.textContaining('DOCUMENTO FICTICIO'), findsOneWidget);

    for (final declaracion in Seed.documentoConsentimiento.declaraciones) {
      await tester.tap(find.text(declaracion));
    }
    final firma = find.byType(SignaturePad);
    await tester.drag(firma, const Offset(100, 20));
    await tester.pump();
    final registrar = tester.widget<AppButton>(
        find.widgetWithText(AppButton, 'Registrar consentimiento'));
    expect(registrar.enabled, isTrue);
    await tester.tap(find.text('Registrar consentimiento'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.textContaining('Datos de prueba'), findsWidgets);

    await tester.tap(find.text('Salir de prueba'));
    await tester.pumpAndSettle();
    expect(find.text('Probar flujo sin conexión'), findsOneWidget);
    expect(sesionReal.usuario, isNull);
  });

  test('la sesión de demostración no acepta configurar ni abrir servidor',
      () async {
    final estado = AppState.demostracion();
    estado.sincronizacion.configurar('https://ejemplo.invalid');
    expect(estado.sincronizacion.configurado, isFalse);
    expect(await estado.sincronizacion.entrar('cuenta', 'clave'),
        contains('no se sincronizan'));
    expect(await estado.sincronizacion.solicitarTramo(),
        contains('no usa tramos reales'));
    final envio = await estado.sincronizacion.sincronizar();
    expect(envio, isA<SinRed>());
    expect((envio as SinRed).error.detalle, contains('no se sincronizan'));
    estado.dispose();
  });
}
