import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/models/role.dart';
import 'cliente_api.dart';
import 'cliente_remoto.dart';
import 'lote.dart';

/// Consolida un lote local directamente en Firestore.
///
/// Todas las escrituras y el acuse pertenecen a una sola transacción: si se
/// corta la conexión, entra todo o no entra nada. Repetir el mismo lote lee el
/// acuse anterior y no duplica registros.
class ClienteFirebase implements ClienteRemoto {
  ClienteFirebase({
    required this.investigadorId,
    required this.institucionCodigo,
    required this.roles,
    FirebaseFirestore? firestore,
  }) : _firestore = firestore ?? FirebaseFirestore.instance;

  final String investigadorId;
  final String institucionCodigo;
  final Set<Rol> roles;
  final FirebaseFirestore _firestore;
  bool _activa = true;

  @override
  bool get haySesion => _activa;

  @override
  void olvidarSesion() => _activa = false;

  @override
  void cerrar() => _activa = false;

  @override
  Future<ResultadoLote> enviar(Lote lote) async {
    if (!_activa) throw const SesionCaducada('La sesión Firebase se cerró.');
    final escrituras = lote.pacientes.length * 3 +
        lote.consentimientos.length +
        lote.eventos.length +
        lote.auditoria.length +
        1;
    if (escrituras > 490) {
      throw const ErrorDelServidor(
          413, 'Hay demasiados registros para un solo envío.');
    }

    final acuse = _firestore.collection('lotes').doc(lote.id);
    try {
      return await _firestore.runTransaction((tx) async {
        final anterior = await tx.get(acuse);
        if (anterior.exists) {
          return _resultado(lote, yaRecibido: true);
        }

        final comunes = <String, Object?>{
          'autor_uid': investigadorId,
          'institucion_codigo': institucionCodigo,
          'dispositivo_id': lote.dispositivoId,
          'lote_id': lote.id,
          'sincronizado_en': FieldValue.serverTimestamp(),
        };

        for (final enviable in lote.pacientes) {
          final p = enviable.paciente;
          tx.set(_firestore.collection('identidades').doc(p.id), {
            ...comunes,
            'paciente_id': p.id,
            'nombre': p.nombre,
            'numero_historia_clinica': p.numeroHistoriaClinica,
            'telefono_principal': p.telefonoPrincipal,
            'telefono_secundario': p.telefonoSecundario,
          });
          tx.set(_firestore.collection('pacientes').doc(p.id), {
            ...comunes,
            'codigo': p.codigo,
            'edad': p.edad,
            'sexo': p.sexo.name,
            'recolector_id': p.recolectorId,
            'enrolado_en': p.enroladoEn.toUtc().toIso8601String(),
          });
          tx.set(_firestore.collection('asignaciones').doc(p.id), {
            ...comunes,
            'paciente_id': p.id,
            'secuencia_etiqueta': p.secuencia,
            'posicion': p.posicionSecuencia,
            'protocolo': p.protocolo.name,
            'asignado_en': p.asignadoEn.toUtc().toIso8601String(),
          });
        }

        for (final enviable in lote.consentimientos) {
          tx.set(_firestore.collection('consentimientos')
              .doc(enviable.consentimiento.id), {
            ...comunes,
            ...enviable.aJson(),
          });
        }
        for (final enviable in lote.eventos) {
          tx.set(_firestore.collection('eventos').doc(enviable.evento.id), {
            ...comunes,
            ...enviable.aJson(),
            'recolector_id': enviable.evento.recolectorId,
          });
        }
        for (final enviable in lote.auditoria) {
          tx.set(_firestore.collection('auditoria').doc(enviable.entrada.id), {
            ...comunes,
            ...enviable.aJson(),
            'autor_original_id': enviable.entrada.autorId,
            'autor_original_nombre': enviable.entrada.autorNombre,
          });
        }

        tx.set(acuse, {
          ...comunes,
          'registros': lote.registros,
          'aceptados': lote.registros,
        });
        return _resultado(lote, yaRecibido: false);
      });
    } on FirebaseException catch (error) {
      if (error.code == 'unavailable' || error.code == 'deadline-exceeded') {
        throw SinConexion(error.message ?? 'Firebase no está disponible.');
      }
      if (error.code == 'permission-denied' ||
          error.code == 'unauthenticated') {
        throw ErrorDelServidor(403,
            error.message ?? 'Firebase rechazó los permisos del envío.');
      }
      throw ErrorDelServidor(
          500, error.message ?? 'Firebase no pudo guardar el lote.');
    }
  }

  ResultadoLote _resultado(Lote lote, {required bool yaRecibido}) =>
      ResultadoLote(
        loteId: lote.id,
        registros: lote.registros,
        aceptados: lote.registros,
        rechazados: 0,
        detalle: const [],
        yaRecibido: yaRecibido,
      );
}
