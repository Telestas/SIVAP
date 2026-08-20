import 'package:flutter_test/flutter_test.dart';
import 'package:sivap/data/local/db/database_key.dart';
import 'package:sivap/data/local/demo_dataset.dart';
import 'package:sivap/data/local/seed_data.dart';

/// Pruebas del almacén local que no necesitan un dispositivo.
///
/// Lo que SÍ necesita dispositivo —abrir SQLCipher, comprobar que la base
/// queda ilegible sin la clave, que el disparador de auditoría aborta un
/// UPDATE— va en `integration_test/`, porque requiere la biblioteca nativa.
/// Ver la lista al final de este archivo.
void main() {
  group('clave de cifrado', () {
    test('son 256 bits en hexadecimal', () {
      final clave = DatabaseKey.generar();

      expect(clave.length, 64, reason: '32 bytes en hex');
      expect(RegExp(r'^[0-9a-f]{64}$').hasMatch(clave), isTrue);
    });

    test('cada clave generada es distinta', () {
      // Si esto fallara, la clave sería predecible y el cifrado, decorativo.
      final claves = {for (var i = 0; i < 200; i++) DatabaseKey.generar()};

      expect(claves.length, 200);
    });

    test('la entrada del almacén está versionada', () {
      // Para poder rotar la clave algún día sin pisar la anterior.
      expect(DatabaseKey.entradaAlmacen, endsWith('.v1'));
    });
  });

  group('datos de demostración', () {
    test('todo evento de muestra tiene formulario definido', () {
      for (final p in Demo.pacientes) {
        for (final e in p.eventos) {
          expect(Seed.formulario.tieneFormulario(e.tipo), isTrue,
              reason: '${p.id} · ${e.tipo.name}');
        }
      }
    });

    test('los valores de muestra usan claves que la definición declara', () {
      // Si una clave no existe en la definición, ese dato no se vería en
      // pantalla ni saldría en la exportación: sería un dato perdido.
      for (final p in Demo.pacientes) {
        for (final e in p.eventos) {
          final claves = Seed.formulario
              .para(e.tipo)!
              .campos
              .map((c) => c.key)
              .toSet();
          for (final clave in e.valores.keys) {
            expect(claves, contains(clave),
                reason: '${e.tipo.name} no declara «$clave»');
          }
        }
      }
    });

    test('un hito no repetible no aparece dos veces en un paciente', () {
      for (final p in Demo.pacientes) {
        final noRepetibles =
            p.eventos.where((e) => !e.tipo.repetible).map((e) => e.tipo).toList();
        expect(noRepetibles.length, noRepetibles.toSet().length,
            reason: p.id);
      }
    });

    test('los identificadores de demostración no se repiten', () {
      expect(Demo.pacientes.map((p) => p.id).toSet().length,
          Demo.pacientes.length);
    });

    test('la auditoría de muestra apunta a pacientes que existen', () {
      for (final a in Demo.auditoria) {
        expect(() => Demo.porId(a.pacienteId), returnsNormally,
            reason: a.pacienteId);
      }
    });

    test('toda corrección de muestra lleva motivo', () {
      for (final a in Demo.auditoria) {
        expect(a.motivo.trim(), isNotEmpty);
      }
    });
  });
}

// ── Pendiente en integration_test/ (necesita dispositivo o emulador) ──
//
// 1. Abrir la base y comprobar que `PRAGMA cipher_version` responde: si no
//    responde, la app debe abortar con CifradoNoDisponible.
// 2. Escribir un paciente, cerrar, y comprobar que el archivo .db NO contiene
//    su nombre en claro (leerlo como bytes y buscar la cadena).
// 3. Reabrir con una clave distinta y comprobar que falla.
// 4. Intentar `UPDATE auditoria SET motivo = 'x'` y comprobar que el
//    disparador aborta.
// 5. Enrolar, cerrar la app, reabrir y enrolar otra vez: el segundo paciente
//    debe recibir la posición siguiente de la secuencia, no la primera.
//    Es el fallo más grave que podría tener la persistencia.
// 6. Abrir dos borradores del mismo hito para el mismo paciente: el índice
//    parcial `idx_un_borrador_por_tipo` debe impedirlo.
