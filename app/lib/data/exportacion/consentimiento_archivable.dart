import '../../domain/models/consent.dart';

/// Documento autónomo: texto aprobado, aceptación y firma visible en un HTML.
/// Puede conservarse como archivo o imprimirse como PDF desde el navegador.
String consentimientoArchivable(Consent c, String codigoPaciente) {
  final documento = c.documentoFirmado;
  if (documento == null || c.firmaTrazos.isEmpty) {
    throw StateError('Este consentimiento no conserva el texto y la firma.');
  }
  String escapar(String valor) => valor
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&#39;');
  final trazos = c.firmaTrazos.map((trazo) {
    final puntos = trazo
        .map((p) => '${(p.x.clamp(0, 1) * 600).toStringAsFixed(1)},'
            '${(p.y.clamp(0, 1) * 180).toStringAsFixed(1)}')
        .join(' ');
    return '<polyline points="$puntos" fill="none" stroke="#172a41" '
        'stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>';
  }).join();
  return '''<!doctype html>
<html lang="es"><head><meta charset="utf-8">
<title>Consentimiento ${escapar(codigoPaciente)}</title>
<style>body{font:16px/1.6 sans-serif;max-width:760px;margin:32px auto;color:#172a41}
header{border-bottom:2px solid #172a41;margin-bottom:24px}p{white-space:pre-wrap}
svg{border:1px solid #9aa6b2;width:600px;max-width:100%;height:180px}
@media print{body{margin:12mm}}</style></head><body>
<header><h1>Consentimiento informado firmado</h1>
<p>Paciente: ${escapar(codigoPaciente)} · ID: ${escapar(c.patientId)}</p>
<p>Versión: ${escapar(c.versionDocumento)} · Código CEI: ${escapar(c.codigoCei)}<br>
Vigente desde: ${escapar(documento.vigenteDesde)}<br>
Firmado: ${escapar(c.firmadoEn.toUtc().toIso8601String())}<br>
Investigador testigo: ${escapar(c.testigoId)} · Registro: ${escapar(c.id)}</p></header>
${documento.parrafos.map((p) => '<p>${escapar(p)}</p>').join('\n')}
<h2>Declaraciones aceptadas</h2><ul>
${documento.declaraciones.map((d) => '<li>${escapar(d)}</li>').join('\n')}
</ul><h2>Firma</h2>
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 600 180" role="img" aria-label="Firma capturada">$trazos</svg>
</body></html>''';
}
