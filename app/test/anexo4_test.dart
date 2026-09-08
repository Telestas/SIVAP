import 'package:flutter_test/flutter_test.dart';
import 'package:sivap/data/local/anexo4.dart';
import 'package:sivap/domain/models/estudio_form_definition.dart';
import 'package:sivap/domain/models/evento_clinico.dart';

/// El Anexo 4 revisado.
///
/// Lo que se comprueba aquí es que el formulario no pueda dejar sin registrar
/// un dato real, y que lo que se esconde se esconda de verdad — incluido el
/// valor guardado, no solo el control en pantalla.
void main() {
  EventoDefinicion definicionDe(TipoEvento tipo) =>
      Anexo4.definicion.para(tipo)!;

  FieldDefinition campo(TipoEvento tipo, String key) =>
      definicionDe(tipo).campos.firstWhere((c) => c.key == key);

  group('criterios de exclusión', () {
    final enrolamiento = Anexo4.definicion.para(TipoEvento.enrolamiento)!;

    test('el enrolamiento abre con la puerta de exclusión', () {
      final puerta = enrolamiento.puertaDeExclusion;

      expect(puerta, isNotNull);
      expect(enrolamiento.secciones.first, same(puerta));
      expect(puerta!.campos.length, 5);
    });

    test('sin ningún criterio marcado, el paciente es elegible', () {
      expect(enrolamiento.puertaDeExclusion!.excluye(const {}), isFalse);
      expect(
        enrolamiento.puertaDeExclusion!
            .excluye(const {'exclusion_glasgow': false}),
        isFalse,
      );
    });

    test('basta un criterio para excluir, y se dice cuál', () {
      final puerta = enrolamiento.puertaDeExclusion!;
      const valores = {
        'exclusion_glasgow': false,
        'exclusion_traqueostomia': true,
      };

      expect(puerta.excluye(valores), isTrue);
      expect(puerta.criteriosMarcados(valores).single.key,
          'exclusion_traqueostomia');
    });
  });

  group('IMC', () {
    double? imc(num peso, num talla) => Calculos.resolver(
        campo(TipoEvento.enrolamiento, 'imc'),
        {'peso': peso, 'talla': talla}) as double?;

    String? categoria(num valor) => Calculos.resolver(
        campo(TipoEvento.enrolamiento, 'categoria_imc'),
        {'imc': valor}) as String?;

    test('se calcula con la fórmula del Anexo', () {
      expect(imc(70, 1.75), 22.9);
      expect(imc(104, 1.70), 36.0);
    });

    test('sin peso o sin talla no hay IMC, y no es cero', () {
      expect(imc(70, 0), isNull);
      expect(
        Calculos.resolver(
            campo(TipoEvento.enrolamiento, 'imc'), const {'peso': 70}),
        isNull,
      );
    });

    test('los tramos no dejan ningún IMC sin categoría', () {
      // El documento escribía «30-39,9» y «>40»: un IMC de 40,0 exacto, o de
      // 39,95, no entraba en ninguna casilla.
      expect(categoria(39.9), 'Obeso');
      expect(categoria(39.95), 'Obeso');
      expect(categoria(40), 'Superobeso');

      expect(categoria(18.4), 'Bajo peso');
      expect(categoria(18.5), 'Normopeso');
      expect(categoria(24.9), 'Normopeso');
      expect(categoria(25), 'Sobrepeso');
      expect(categoria(29.9), 'Sobrepeso');
      expect(categoria(30), 'Obeso');
    });

    test('la categoría que se calcula es una de las declaradas', () {
      final opciones = campo(TipoEvento.enrolamiento, 'categoria_imc').opciones;

      for (final valor in [15, 20, 27, 33, 45]) {
        expect(opciones, contains(categoria(valor)));
      }
    });
  });

  group('estratificación de riesgo', () {
    String? nivel(Map<String, Object?> factores) => Calculos.resolver(
        campo(TipoEvento.enrolamiento, 'estratificacion_riesgo'),
        factores) as String?;

    Map<String, Object?> factores(int presentes) {
      const claves = [
        'factor_edad',
        'factor_obesidad',
        'factor_epoc',
        'factor_insuficiencia_cardiaca',
        'factor_via_aerea',
      ];
      return {
        for (var i = 0; i < claves.length; i++) claves[i]: i < presentes,
      };
    }

    test('alto con cuatro factores o más', () {
      expect(nivel(factores(4)), 'Alto');
      expect(nivel(factores(5)), 'Alto');
    });

    test('moderado de uno a tres', () {
      expect(nivel(factores(1)), 'Moderado');
      expect(nivel(factores(3)), 'Moderado');
    });

    test('bajo solo cuando los cinco están contestados y ninguno presente', () {
      expect(nivel(factores(0)), 'Bajo');
    });

    test('con el formulario en blanco no hay nivel', () {
      // Decir «bajo riesgo» sin haber comprobado nada es afirmar algo que
      // nadie miró.
      expect(nivel(const {}), isNull);
      expect(nivel(const {'factor_edad': false}), isNull);
    });
  });

  group('campos condicionales', () {
    test('la causa del fallo solo aparece si la PVE falló', () {
      final causa =
          campo(TipoEvento.pruebaVentilacionEspontanea, 'causa_fallo_pve');

      expect(causa.visibleCon(const {}), isFalse);
      expect(causa.visibleCon(const {'resultado_pve': 'Éxito'}), isFalse);
      expect(causa.visibleCon(const {'resultado_pve': 'Fallo'}), isTrue);
    });

    test('la fecha de traqueostomía solo aparece si se hizo', () {
      final fecha = campo(TipoEvento.extubacion, 'fecha_traqueostomia');

      expect(fecha.visibleCon(const {'traqueostomia': false}), isFalse);
      expect(fecha.visibleCon(const {'traqueostomia': true}), isTrue);
    });

    test('el motivo del fallecimiento depende del estado al egreso', () {
      final causa = campo(TipoEvento.desenlaces, 'causa_fallecimiento');
      final egreso = campo(TipoEvento.desenlaces, 'fecha_egreso_uci');

      expect(causa.visibleCon(const {'estado_egreso': 'Fallecido'}), isTrue);
      expect(causa.visibleCon(const {'estado_egreso': 'Vivo'}), isFalse);
      expect(egreso.visibleCon(const {'estado_egreso': 'Vivo'}), isTrue);
    });

    test('lo que no se ve no se exige', () {
      final pve = definicionDe(TipoEvento.pruebaVentilacionEspontanea);

      expect(
        pve.obligatoriosVisibles(const {'resultado_pve': 'Éxito'})
            .map((c) => c.key),
        isNot(contains('causa_fallo_pve')),
      );
    });

    test('toda condición apunta a un campo que existe y a un valor posible',
        () {
      for (final evento in Anexo4.definicion.eventos) {
        final claves = {for (final c in evento.campos) c.key};
        for (final c in evento.campos.where((c) => c.dependeDe != null)) {
          expect(claves, contains(c.dependeDe),
              reason: '${c.key} depende de un campo que no está en su evento');
          expect(c.visibleCuando, isNotEmpty,
              reason: '${c.key} depende de algo pero no dice de qué valor');

          final referido =
              evento.campos.firstWhere((o) => o.key == c.dependeDe);
          if (referido.tipo == FieldType.seleccionUnica) {
            expect(referido.opciones, containsAll(c.visibleCuando),
                reason: '${c.key} espera un valor que ${referido.key} no ofrece');
          }
        }
      }
    });
  });

  group('campos calculados', () {
    test('cada cálculo declara de qué campos se alimenta, y existen', () {
      for (final evento in Anexo4.definicion.eventos) {
        final claves = {for (final c in evento.campos) c.key};
        for (final c in evento.campos.where((c) => c.esCalculado)) {
          expect(c.entradasDelCalculo, isNotEmpty,
              reason: '${c.key} se calcula pero no dice con qué');
          expect(claves, containsAll(c.entradasDelCalculo),
              reason: '${c.key} se alimenta de campos que no están en su evento');
        }
      }
    });
  });

  group('tramos sin huecos', () {
    test('quince días exactos tienen casilla', () {
      // «6-14 días» y «>15 días» dejaban fuera al paciente de 15 días justos.
      for (final key in ['duracion_total_vmi']) {
        expect(campo(TipoEvento.extubacion, key).opciones,
            contains('15 días o más'));
      }
      expect(campo(TipoEvento.desenlaces, 'estancia_uci').opciones,
          contains('15 días o más'));
    });

    test('el soporte post-extubación no se acaba en 72 horas', () {
      expect(campo(TipoEvento.extubacion, 'tiempo_soporte').opciones.last,
          '72 h o más');
    });

    test('las duraciones de la PVE no se solapan', () {
      expect(campo(TipoEvento.pruebaVentilacionEspontanea, 'duracion_pve')
          .opciones,
          ['Menos de 30 min', 'De 30 a 59 min', 'De 60 a 119 min',
           '120 min o más']);
    });
  });

  group('vocabulario del dataset', () {
    test('no hay dos campos con la misma clave dentro de un evento', () {
      for (final evento in Anexo4.definicion.eventos) {
        final claves = evento.campos.map((c) => c.key).toList();
        expect(claves.length, claves.toSet().length,
            reason: 'clave repetida en ${evento.tipo.name}');
      }
    });

    test('el modo ventilatorio se pregunta con la misma lista en los dos sitios',
        () {
      // Si divergieran, el dataset tendría dos vocabularios para lo mismo.
      expect(
        campo(TipoEvento.pruebaVentilacionEspontanea,
                'modo_ventilatorio_previo')
            .opciones,
        campo(TipoEvento.extubacion, 'modo_ventilatorio_previo_extubacion')
            .opciones,
      );
    });

    test('la causa de la intubación no ofrece categorías que se solapen', () {
      // «Respiratoria» y «EPOC exacerbada» no son alternativas si la primera
      // no se acota: el mismo paciente se codificaría de dos formas, y eso
      // cambia su estratificación de riesgo.
      final opciones = campo(TipoEvento.enrolamiento, 'causa_intubacion')
          .opciones;

      expect(opciones, contains('Respiratoria (otras causas)'));
      expect(opciones, contains('EPOC exacerbada'));
      expect(opciones, contains('Cardiovascular (otras causas)'));
      expect(opciones, contains('Insuficiencia cardíaca'));
      expect(opciones, isNot(contains('Respiratoria')));
    });
  });
}
