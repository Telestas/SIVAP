import 'package:flutter/material.dart';

import '../../domain/models/protocolo.dart';
import '../../domain/models/visit.dart';
import '../theme/tokens.dart';

/// Chip de rama del estudio. El color codifica la rama en toda la app.
class ProtocolChip extends StatelessWidget {
  const ProtocolChip(this.protocolo, {super.key, this.largo = false, this.fontSize = 11});

  final Protocolo protocolo;
  final bool largo;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final nuevo = protocolo == Protocolo.nuevo;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: largo ? 12 : 9, vertical: largo ? 7 : 4),
      decoration: BoxDecoration(
        color: nuevo ? T.nuevoBg : T.vigenteBg,
        border: Border.all(color: nuevo ? T.nuevoLine : T.vigenteLine),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        largo ? protocolo.nombreLargo : protocolo.chip,
        style: TextStyle(
          fontFamily: T.mono,
          fontSize: fontSize,
          fontWeight: largo ? FontWeight.w700 : FontWeight.w600,
          letterSpacing: fontSize * 0.03,
          color: nuevo ? T.nuevoFg : T.vigenteFg,
        ),
      ),
    );
  }
}

/// Píldora de progreso por visita: D1 · D3 · D5 · D10 · D14.
class DayPill extends StatelessWidget {
  const DayPill({super.key, required this.dia, required this.status});

  final int dia;
  final VisitStatus status;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = switch (status) {
      VisitStatus.enviada => (T.okBg, T.okFg),
      VisitStatus.enCaptura => (T.warnBg, T.warnFg),
      VisitStatus.perdida => (T.dangerBg, T.dangerFg),
      VisitStatus.programada => (T.idleBg, T.idleFg),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(4)),
      child: Text('D$dia',
          style: TextStyle(fontFamily: T.mono, fontSize: 10.5, color: fg, height: 1.2)),
    );
  }
}

/// Leyenda de las píldoras. Sin ella, el color no se interpreta solo.
class DayPillLegend extends StatelessWidget {
  const DayPillLegend({super.key});

  @override
  Widget build(BuildContext context) => const DefaultTextStyle(
        style: TextStyle(fontFamily: T.mono, fontSize: 10, color: T.faint),
        child: const Row(children: [
          Text('■ completa'),
          SizedBox(width: 14),
          Text('■ pendiente', style: TextStyle(fontFamily: T.mono, fontSize: 10, color: T.warnFg)),
          SizedBox(width: 14),
          Text('■ perdida', style: TextStyle(fontFamily: T.mono, fontSize: 10, color: T.dangerFg)),
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
          style: T.label(size: 10.5, color: fg, weight: FontWeight.w600, tracking: 0.06)),
    );
  }
}

enum MetaTone { neutro, aviso, ok }
