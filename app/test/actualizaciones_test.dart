import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sivap/app.dart';
import 'package:sivap/core/app_state.dart';
import 'package:sivap/data/local/almacen_local.dart';
import 'package:sivap/data/local/in_memory_study_repository.dart';
import 'package:sivap/data/local/seed_data.dart';
import 'package:sivap/data/remoto/actualizaciones.dart';
import 'package:sivap/features/patients/patient_list_screen.dart';

void main() {
  final versiones = [
    {
      'tag_name': 'v0.2.5',
      'draft': true,
      'assets': [
        {'name': 'sivap-0.2.5-arm64.apk'}
      ],
    },
    {
      'tag_name': 'v0.2.4',
      'draft': false,
      'prerelease': true,
      'assets': [
        {'name': 'sivap-0.2.4-arm64.apk'}
      ],
    },
    {
      'tag_name': 'v0.2.6',
      'draft': false,
      'assets': [],
    },
  ];

  test('avisa solo de una versión publicada que tenga APK', () {
    expect(Actualizaciones.versionNueva(versiones, '0.2.3'), '0.2.4');
    expect(Actualizaciones.versionNueva(versiones, '0.2.4'), isNull);
  });

  testWidgets('la campana muestra la nueva versión y abre la descarga',
      (tester) async {
    tester.view.physicalSize = const Size(420, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    Uri? paginaAbierta;
    var consultas = 0;
    final actualizaciones = Actualizaciones(
      cliente: MockClient((_) async {
        consultas++;
        return http.Response(jsonEncode(versiones), 200);
      }),
      leerVersionInstalada: () async => '0.2.3',
      abrirDescarga: (uri) async {
        paginaAbierta = uri;
        return true;
      },
    );
    final estado = AppState(
      AlmacenLocal(
        repo: InMemoryStudyRepository(),
        persistente: false,
        cifrado: false,
        descripcion: 'Prueba',
      ),
      actualizaciones: actualizaciones,
    )..iniciarSesion(Seed.reclutador);
    addTearDown(estado.dispose);

    await tester
        .pumpWidget(raizDeLaApp(estado, inicio: const PatientListScreen()));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Nueva versión disponible'), findsOneWidget);
    await tester.tap(find.byTooltip('Nueva versión disponible'));
    await tester.pumpAndSettle();
    expect(find.text('Tienes una nueva versión disponible: v0.2.4.'),
        findsOneWidget);
    await tester.tap(find.text('Descargar actualización'));
    await tester.pump();
    expect(paginaAbierta, Actualizaciones.paginaDescarga);

    await tester.tap(find.text('Cerrar'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Opciones de la cuenta'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Buscar actualización'));
    await tester.pumpAndSettle();
    expect(consultas, 2);
  });

  test('un fallo de red no inventa una notificación', () async {
    final actualizaciones = Actualizaciones(
      cliente: MockClient((_) async => http.Response('Bloqueado', 403)),
      leerVersionInstalada: () async => '0.2.3',
    );
    await actualizaciones.buscar();
    expect(actualizaciones.hayNuevaVersion, isFalse);
    expect(actualizaciones.error, contains('VPN'));
    actualizaciones.dispose();
  });
}
