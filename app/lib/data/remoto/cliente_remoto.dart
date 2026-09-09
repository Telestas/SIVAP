import 'lote.dart';

/// Contrato mínimo que consume la cola local.
///
/// FastAPI y Firebase lo implementan sin que el almacenamiento local sepa a
/// cuál de los dos está enviando.
abstract class ClienteRemoto {
  bool get haySesion;
  void olvidarSesion();
  void cerrar();
  Future<ResultadoLote> enviar(Lote lote);
}
