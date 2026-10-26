import 'dart:convert';

import 'package:archive/archive.dart';

import '../../domain/models/role.dart';
import '../../domain/repositories/study_repository.dart';

/// Genera dos libros separados desde la vista autorizada del centro.
/// Ningún campo identificable entra en el libro clínico.
class XlsxEstudio {
  static List<int> clinico(StudyRepository repo, Investigador autor) {
    if (!autor.puedeExportar || !autor.veRamaAsignada) {
      throw StateError('Su función no puede exportar la cohorte clínica.');
    }
    final filas = <List<Object?>>[
      [
        'paciente_id',
        'codigo',
        'institucion',
        'edad',
        'sexo',
        'protocolo',
        'evento_id',
        'tipo',
        'ocurrencia',
        'fecha_ocurrencia',
        'campo',
        'valor'
      ],
    ];
    for (final p in repo.pacientes()) {
      if (p.institucion.codigo != autor.institucion.codigo) continue;
      final eventos = repo.eventosDe(p.id);
      if (eventos.isEmpty) {
        filas.add([
          p.id,
          p.codigo,
          p.institucion.codigo,
          p.edad,
          p.sexo.name,
          p.protocolo.letra,
          null,
          null,
          null,
          null,
          null,
          null
        ]);
      }
      for (final e in eventos) {
        for (final campo in e.valores.entries) {
          filas.add([
            p.id,
            p.codigo,
            p.institucion.codigo,
            p.edad,
            p.sexo.name,
            p.protocolo.letra,
            e.id,
            e.tipo.name,
            e.ocurrencia,
            e.fechaOcurrencia.toIso8601String(),
            campo.key,
            campo.value
          ]);
        }
      }
    }
    return _libro(filas);
  }

  static List<int> identidad(StudyRepository repo, Investigador autor) {
    if (!autor.roles.contains(Rol.investigadorPrincipal)) {
      throw StateError('Solo la investigadora principal exporta identidad.');
    }
    final filas = <List<Object?>>[
      [
        'paciente_id',
        'codigo',
        'institucion',
        'nombre',
        'numero_historia_clinica',
        'telefono_principal',
        'telefono_secundario'
      ],
      for (final p in repo.pacientes())
        if (p.institucion.codigo == autor.institucion.codigo)
          [
            p.id,
            p.codigo,
            p.institucion.codigo,
            p.nombre,
            p.numeroHistoriaClinica,
            p.telefonoPrincipal,
            p.telefonoSecundario
          ],
    ];
    return _libro(filas);
  }

  static List<int> _libro(List<List<Object?>> filas) {
    final hoja = StringBuffer(
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData>',
    );
    for (var i = 0; i < filas.length; i++) {
      hoja.write('<row r="${i + 1}">');
      for (var j = 0; j < filas[i].length; j++) {
        final valor = filas[i][j];
        if (valor == null) continue;
        final celda = '${_columna(j)}${i + 1}';
        if (valor is num) {
          hoja.write('<c r="$celda"><v>$valor</v></c>');
        } else {
          // El tipo inlineStr impide que una entrada clínica se evalúe como
          // fórmula al abrir el libro en Excel o LibreOffice.
          hoja.write(
              '<c r="$celda" t="inlineStr"><is><t>${_xml(valor.toString())}</t></is></c>');
        }
      }
      hoja.write('</row>');
    }
    hoja.write('</sheetData></worksheet>');
    final zip = Archive();
    void agregar(String ruta, String contenido) {
      final bytes = utf8.encode(contenido);
      zip.addFile(ArchiveFile(ruta, bytes.length, bytes));
    }

    agregar(
        '[Content_Types].xml',
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
            '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
            '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
            '<Default Extension="xml" ContentType="application/xml"/>'
            '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
            '<Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'
            '</Types>');
    agregar(
        '_rels/.rels',
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
            '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
            '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>'
            '</Relationships>');
    agregar(
        'xl/workbook.xml',
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
            '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
            'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
            '<sheets><sheet name="Datos" sheetId="1" r:id="rId1"/></sheets></workbook>');
    agregar(
        'xl/_rels/workbook.xml.rels',
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
            '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
            '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>'
            '</Relationships>');
    agregar('xl/worksheets/sheet1.xml', hoja.toString());
    return ZipEncoder().encode(zip)!;
  }

  static String _columna(int indice) {
    var n = indice + 1;
    var resultado = '';
    while (n > 0) {
      n--;
      resultado = String.fromCharCode(65 + n % 26) + resultado;
      n ~/= 26;
    }
    return resultado;
  }

  static String _xml(String valor) => valor
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');
}
