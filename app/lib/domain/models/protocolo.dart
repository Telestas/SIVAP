/// Rama del estudio. "Vigente" es el control; "nuevo" es el que se valida.
enum Protocolo {
  vigente('PROT. VIGENTE', 'PROTOCOLO VIGENTE', 'Rama control'),
  nuevo('PROT. NUEVO', 'PROTOCOLO NUEVO', 'Rama experimental');

  const Protocolo(this.chip, this.nombreLargo, this.rama);
  final String chip;
  final String nombreLargo;
  final String rama;
}
