import 'package:flutter/material.dart';

import '../../domain/models/evento_clinico.dart';
import '../../domain/models/protocolo.dart';
import '../theme/tokens.dart';

/// Distintivo de rama del ensayo.
///
/// Muestra «PROT. A» o «PROT. B» y nada más. No hay variante que diga cuál es
/// la rama en estudio porque el sistema no lo sabe (CLAUDE.md §2).
class ProtocolChip extends StatelessWidget {
  const ProtocolChip(this.protocolo,
      {super.key, this.largo = false, this.fontSize = 11});

  final Protocolo protocolo;
  final bool largo;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final esA = protocolo == Protocolo.a;
    return Container(
      padding:
          EdgeInsets.symmetric(horizontal: largo ? 12 : 9, vertical: largo ? 7 : 4),
      decoration: BoxDecoration(
        color: esA ? T.ramaABg : T.ramaBBg,
        border: Border.all(color: esA ? T.ramaALine : T.ramaBLine),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        largo ? protocolo.nombreLargo : protocolo.chip,
        style: TextStyle(
          fontFamily: T.mono,
          fontFamilyFallback: T.monoFallback,
          fontSize: fontSize,
          fontWeight: largo ? FontWeight.w700 : FontWeight.w600,
          letterSpacing: fontSize * 0.03,
          color: esA ? T.ramaAFg : T.ramaBFg,
        ),
      ),
    );
  }
}

/// Indicador compacto del avance por fases del proceso de liberación.
///
/// Sustituye a las píldoras de día del modelo anterior. No dice si una fase
/// «falta»: en un ensayo dirigido por eventos no hay forma de saber qué tenía
/// que ocurrir, solo qué ocurrió (CLAUDE.md §4).
class FasePill extends StatelessWidget {
  const FasePill({
    super.key,
    required this.fase,
    required this.registrados,
    this.enBorrador = false,
  });

  final FaseEstudio fase;

  /// Cuántos eventos de esa fase se han registrado.
  final int registrados;

  /// Si hay un borrador abierto en la fase.
  final bool enBorrador;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = enBorrador
        ? (T.warnBg, T.warnFg)
        : registrados > 0
            ? (T.okBg, T.okFg)
            : (T.idleBg, T.idleFg);

    return Tooltip(
      message: '${fase.etiqueta} · '
          '${registrados == 0 ? 'sin registros' : '$registrados registrado(s)'}',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(4)),
        child: Text(
          fase.abreviatura,
          style: TextStyle(
              fontFamily: T.mono,
              fontFamilyFallback: T.monoFallback,
              fontSize: 10.5,
              color: fg,
              height: 1.2),
        ),
      ),
    );
  }
}

/// Leyenda de las píldoras de fase. Sin ella, el color no se interpreta solo.
class FasePillLegend extends StatelessWidget {
  const FasePillLegend({super.key});

  @override
  Widget build(BuildContext context) => const DefaultTextStyle(
        style: TextStyle(
            fontFamily: T.mono,
            fontFamilyFallback: T.monoFallback,
            fontSize: 10,
            color: T.faint),
        child: Row(children: [
          Text('■ con registros',
              style: TextStyle(
                  fontFamily: T.mono,
                  fontFamilyFallback: T.monoFallback,
                  fontSize: 10,
                  color: T.okFg)),
          SizedBox(width: 14),
          Text('■ en captura',
              style: TextStyle(
                  fontFamily: T.mono,
                  fontFamilyFallback: T.monoFallback,
                  fontSize: 10,
                  color: T.warnFg)),
          SizedBox(width: 14),
          Text('■ sin registros'),
        ]),
      );
}

/// Punto de color del estado de sincronización.
class SyncDot extends StatelessWidget {
  const SyncDot(this.sync, {super.key, this.size = 7});

  final SyncStatus sync;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: sync == SyncStatus.sincronizado ? T.okDot : T.warnDot,
          shape: BoxShape.circle,
        ),
      );
}

/// Chip neutro de metadato: "SOLO LECTURA", "DOC. v2.1", "BORRADOR".
class MetaChip extends StatelessWidget {
  const MetaChip(this.texto, {super.key, this.tono = MetaTone.neutro});

  final String texto;
  final MetaTone tono;

  @override
  Widget build(BuildContext context) {
    final (bg, fg, bd) = switch (tono) {
      MetaTone.neutro => (T.neutralBg, T.neutralFg, T.neutralLine),
      MetaTone.aviso => (T.warnBg, T.warnFg, T.warnLine),
      MetaTone.ok => (T.okBg, T.okFg, T.okLine),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        border: Border.all(color: bd),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(texto,
          style:
              T.label(size: 10.5, color: fg, weight: FontWeight.w600, tracking: 0.06)),
    );
  }
}

enum MetaTone { neutro, aviso, ok }
