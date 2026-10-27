import 'package:cloud_firestore/cloud_firestore.dart';

/// Recoge de forma atómica una reserva preparada por la CLI administrativa.
class ClienteTramosFirestore {
  ClienteTramosFirestore({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;
  final FirebaseFirestore _db;

  Future<Map<String, dynamic>> recoger(String uid, String dispositivoId) =>
      _db.runTransaction((tx) async {
        final reservaRef = _db.collection('reservas_tramos').doc(uid);
        final tramoRef = _db.collection('tramos').doc(dispositivoId);
        final reserva = await tx.get(reservaRef);
        final anterior = await tx.get(tramoRef);
        final datos = reserva.data();
        if (datos == null) {
          throw StateError('Todavía no hay un tramo preparado para su cuenta. '
              'La administración debe reservarlo desde la CLI.');
        }
        final aparato = datos['dispositivo_id'];
        if (aparato != null) {
          if (aparato == dispositivoId && anterior.exists) {
            return anterior.data()!;
          }
          throw StateError('La reserva de esta cuenta ya pertenece a otro '
              'aparato. Solicite una nueva reserva a la administración.');
        }
        final tramo = Map<String, dynamic>.from(datos['tramo'] as Map);
        tx.set(tramoRef, tramo);
        tx.update(reservaRef, {'dispositivo_id': dispositivoId});
        return tramo;
      });
}
