import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sivap/data/exportacion/xlsx_estudio.dart';
import 'package:sivap/data/local/in_memory_study_repository.dart';
import 'package:sivap/data/local/seed_data.dart';

String hoja(List<int> bytes) {
  final archivo = ZipDecoder()
      .decodeBytes(bytes)
      .files
      .singleWhere((f) => f.name == 'xl/worksheets/sheet1.xml');
  return utf8.decode(archivo.content as List<int>);
}

void main() {
  test('el libro clínico excluye identidad y usa ramas A/B', () {
    final repo = InMemoryStudyRepository();
    final xml = hoja(XlsxEstudio.clinico(repo, Seed.analista));
    expect(xml, contains('paciente_id'));
    expect(xml, contains('protocolo'));
    expect(xml, isNot(contains('telefono_principal')));
    expect(xml, isNot(contains('numero_historia_clinica')));
    expect(xml, isNot(contains('nombre')));
    expect(xml, contains('>A<'));
    expect(() => XlsxEstudio.clinico(repo, Seed.evaluador), throwsStateError);
  });

  test('identidad va en otro libro y solo la exporta la principal', () {
    final repo = InMemoryStudyRepository();
    final xml = hoja(XlsxEstudio.identidad(repo, Seed.principal));
    expect(xml, contains('telefono_principal'));
    expect(xml, isNot(contains('protocolo')));
    expect(xml, isNot(contains('fecha_ocurrencia')));
    expect(() => XlsxEstudio.identidad(repo, Seed.analista), throwsStateError);
  });
}
