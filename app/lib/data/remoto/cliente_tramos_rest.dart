import 'firebase_rest_movil.dart';

/// Reclama la reserva y crea el tramo en una sola transacción Firestore.
class ClienteTramosRest {
  ClienteTramosRest(this.rest);
  final FirebaseRestMovil rest;

  Future<Map<String, dynamic>> recoger(String uid, String dispositivoId) async {
    return rest.reintentarTransaccion(() async {
      final transaccion = await rest.comenzarTransaccion();
      final reservaRuta = 'reservas_tramos/$uid';
      final tramoRuta = 'tramos/$dispositivoId';
      final documentos =
          await rest.leerTransaccion(transaccion, [reservaRuta, tramoRuta]);
      const prefijo =
          'projects/${FirebaseRestMovil.proyecto}/databases/(default)/documents/';
      final reserva = documentos['$prefijo$reservaRuta'];
      final anterior = documentos['$prefijo$tramoRuta'];
      if (reserva == null) {
        throw StateError('Todavía no hay un tramo preparado para su cuenta. '
            'La administración debe reservarlo desde la CLI.');
      }
      final aparato = reserva['dispositivo_id'];
      if (aparato != null) {
        if (aparato == dispositivoId && anterior != null) return anterior;
        throw StateError('La reserva de esta cuenta ya pertenece a otro '
            'aparato. Solicite una nueva reserva a la administración.');
      }
      final tramo = Map<String, dynamic>.from(reserva['tramo'] as Map);
      await rest.commit([
        FirebaseRestMovil.escritura(tramoRuta, tramo, crear: true),
        FirebaseRestMovil.escritura(
            reservaRuta, {'dispositivo_id': dispositivoId},
            camposActualizar: const ['dispositivo_id']),
      ], transaccion: transaccion);
      return tramo;
    });
  }
}
