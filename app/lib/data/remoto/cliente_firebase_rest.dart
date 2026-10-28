import '../../domain/models/role.dart';
import 'cliente_api.dart';
import 'cliente_remoto.dart';
import 'firebase_rest_movil.dart';
import 'lote.dart';

/// Consolida la cola por Cloudflare en una transacción Firestore.
/// El acuse y todos los documentos se confirman juntos; repetir el lote es seguro.
class ClienteFirebaseRest implements ClienteRemoto {
  ClienteFirebaseRest({
    required this.rest,
    required this.investigadorId,
    required this.institucionCodigo,
    required this.roles,
  });

  final FirebaseRestMovil rest;
  final String investigadorId;
  final String institucionCodigo;
  final Set<Rol> roles;
  bool _activa = true;

  @override
  bool get haySesion => _activa && rest.haySesion;

  @override
  void olvidarSesion() => _activa = false;

  @override
  void cerrar() => _activa = false;

  @override
  Future<ResultadoLote> enviar(Lote lote) async {
    if (!haySesion) throw const SesionCaducada('La sesión Firebase se cerró.');
    final cantidad = lote.pacientes.length * 4 +
        lote.consentimientos.length +
        lote.eventos.length +
        lote.auditoria.length +
        1;
    if (cantidad > 490) {
      throw const ErrorDelServidor(
          413, 'Hay demasiados registros para un solo envío.');
    }
    try {
      return await rest.reintentarTransaccion(() async {
        final transaccion = await rest.comenzarTransaccion();
        final acuseRuta = 'lotes/${lote.id}';
        final documentos = await rest.leerTransaccion(transaccion, [acuseRuta]);
        const prefijo =
            'projects/${FirebaseRestMovil.proyecto}/databases/(default)/documents/';
        if (documentos['$prefijo$acuseRuta'] != null) {
          return _resultado(lote, yaRecibido: true);
        }
        final comunes = <String, Object?>{
          'autor_uid': investigadorId,
          'institucion_codigo': institucionCodigo,
          'dispositivo_id': lote.dispositivoId,
          'lote_id': lote.id,
        };
        final escrituras = <Map<String, Object?>>[];
        void agregar(String ruta, Map<String, Object?> datos) {
          escrituras.add(FirebaseRestMovil.escritura(
              ruta, {...comunes, ...datos},
              crear: true, tiempos: const ['sincronizado_en']));
        }

        for (final enviable in lote.pacientes) {
          final p = enviable.paciente;
          agregar('identidades/${p.id}', {
            'paciente_id': p.id,
            'nombre': p.nombre,
            'numero_historia_clinica': p.numeroHistoriaClinica,
            'telefono_principal': p.telefonoPrincipal,
            'telefono_secundario': p.telefonoSecundario,
          });
          agregar('pacientes/${p.id}', {
            'codigo': p.codigo,
            'edad': p.edad,
            'sexo': p.sexo.name,
            'recolector_id': p.recolectorId,
            'enrolado_en': p.enroladoEn.toUtc().toIso8601String(),
          });
          agregar('asignaciones/${p.id}', {
            'paciente_id': p.id,
            'secuencia_etiqueta': p.secuencia,
            'posicion': p.posicionSecuencia,
            'protocolo': p.protocolo.name,
            'asignado_en': p.asignadoEn.toUtc().toIso8601String(),
          });
          agregar('posiciones/${p.posicionSecuencia}', {
            'paciente_id': p.id,
            'posicion': p.posicionSecuencia,
            'secuencia_etiqueta': p.secuencia,
          });
        }
        for (final enviable in lote.consentimientos) {
          agregar('consentimientos/${enviable.consentimiento.id}',
              enviable.aJsonFirestore());
        }
        for (final enviable in lote.eventos) {
          agregar('eventos/${enviable.evento.id}', {
            ...enviable.aJson(),
            'recolector_id': enviable.evento.recolectorId,
          });
        }
        for (final enviable in lote.auditoria) {
          agregar('auditoria/${enviable.entrada.id}', {
            ...enviable.aJson(),
            'autor_original_id': enviable.entrada.autorId,
            'autor_original_nombre': enviable.entrada.autorNombre,
          });
        }
        agregar(acuseRuta, {
          'registros': lote.registros,
          'aceptados': lote.registros,
        });
        await rest.commit(escrituras, transaccion: transaccion);
        return _resultado(lote, yaRecibido: false);
      });
    } on FirebaseRestError catch (error) {
      if (error.estado == 0 || error.estado == 502 || error.estado == 503) {
        throw SinConexion(error.mensaje);
      }
      throw ErrorDelServidor(error.estado, error.mensaje);
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
