import 'package:flutter_test/flutter_test.dart';
import 'package:sivap/data/local/demo_dataset.dart';
import 'package:sivap/data/local/seed_data.dart';
import 'package:sivap/domain/models/protocolo.dart';

/// El cegamiento, como prueba.
///
/// **Restricción no negociable (CLAUDE.md §2).** El sistema conoce dos ramas,
/// A y B. Cuál es LIVERE y cuál el manejo convencional no está en el código, ni
/// en la base, ni en las exportaciones, ni en los logs.
///
/// Si algo de esto falla, no se relaja la aserción: se corrige el código. Un
/// ensayo cuyo cegamiento se rompe por la herramienta de captura pierde validez
/// interna, y eso no se arregla después.
void main() {
  /// Palabras que dejarían ver qué rama es cuál.
  const prohibidas = [
    'nuevo',
    'vigente',
    'control',
    'experimental',
    'livere',
    'convencional',
    'intervención',
    'placebo',
  ];

  group('las ramas se llaman A y B', () {
    test('hay exactamente dos', () {
      expect(Protocolo.values.length, 2);
    });

    test('se identifican solo por letra', () {
      expect(Protocolo.a.letra, 'A');
      expect(Protocolo.b.letra, 'B');
      expect(Protocolo.values.map((p) => p.name).toSet(), {'a', 'b'});
    });

    test('ninguna etiqueta insinúa qué rama es cuál', () {
      for (final p in Protocolo.values) {
        for (final texto in [p.name, p.chip, p.nombreLargo, p.letra]) {
          for (final palabra in prohibidas) {
            expect(
              texto.toLowerCase(),
              isNot(contains(palabra)),
              reason: '«$texto» contiene «$palabra»: revela la rama',
            );
          }
        }
      }
    });

    test('las etiquetas son exactamente las esperadas', () {
      // Fijadas a propósito: si alguien las cambia, esta prueba obliga a pensar
      // si el cambio sigue siendo ciego.
      expect(Protocolo.a.chip, 'PROT. A');
      expect(Protocolo.b.chip, 'PROT. B');
      expect(Protocolo.a.nombreLargo, 'PROTOCOLO A');
      expect(Protocolo.b.nombreLargo, 'PROTOCOLO B');
    });
  });

  group('la correspondencia no está en ninguna parte del sistema', () {
    test('el documento de consentimiento no la revela', () {
      const doc = Seed.documentoConsentimiento;
      final texto =
          [...doc.parrafos, ...doc.declaraciones].join(' ').toLowerCase();

      for (final palabra in ['livere', 'convencional', 'experimental']) {
        expect(texto, isNot(contains(palabra)),
            reason: 'el consentimiento menciona «$palabra»');
      }
    });

    test('los datos de demostración no la revelan', () {
      final texto = Demo.pacientes
          .expand((p) => p.eventos)
          .expand((e) => e.valores.values)
          .whereType<String>()
          .join(' ')
          .toLowerCase();

      for (final palabra in ['livere', 'convencional']) {
        expect(texto, isNot(contains(palabra)));
      }
    });

    test('la secuencia solo contiene ramas, no significados', () {
      // El código binario es 0/1. Qué significa cada dígito lo sabe el
      // expediente en papel, no este archivo.
      expect(RegExp(r'^[01]+$')
          .hasMatch(Seed.secuenciaAleatorizacion.codigoBinario), isTrue);
    });
  });

  group('nada identificable en los datos de demostración', () {
    test('el estudio arranca sin semilla real', () {
      // La semilla real se genera fuera y nunca entra al repositorio
      // (CLAUDE.md §7). Esta es de demostración y está declarada como tal.
      expect(Seed.secuenciaAleatorizacion.etiqueta, contains('demostración'));
    });

    test('los investigadores de demostración no llevan nombres reales', () {
      for (final i in Seed.investigadores) {
        expect(i.nombre.split(' ').length, lessThanOrEqualTo(2),
            reason: '«${i.nombre}» parece un nombre real');
      }
    });
  });
}
