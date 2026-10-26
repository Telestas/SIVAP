import {onCall, HttpsError} from 'firebase-functions/v2/https';
import {initializeApp} from 'firebase-admin/app';
import {getFirestore} from 'firebase-admin/firestore';
import {siguienteTramo} from './tramo.mjs';

initializeApp();

/** Reparte tramos disjuntos sin publicar la secuencia al cliente. */
export const solicitarTramo = onCall({region: 'us-central1'}, async (request) => {
  const uid = request.auth?.uid;
  const dispositivoId = request.data?.dispositivo_id;
  if (!uid) throw new HttpsError('unauthenticated', 'Abra sesión primero.');
  if (typeof dispositivoId !== 'string' ||
      !/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/.test(dispositivoId)) {
    throw new HttpsError('invalid-argument', 'Dispositivo inválido.');
  }

  const db = getFirestore();
  const perfilRef = db.collection('investigadores').doc(uid);
  const dispositivoRef = db.collection('dispositivos').doc(dispositivoId);
  const secuenciaRef = db.collection('aleatorizacion').doc('activa');
  const tramoRef = db.collection('tramos').doc(dispositivoId);

  return db.runTransaction(async (tx) => {
    const [perfilDoc, dispositivoDoc, secuenciaDoc, tramoDoc] = await Promise.all([
      tx.get(perfilRef), tx.get(dispositivoRef), tx.get(secuenciaRef),
      tx.get(tramoRef),
    ]);
    const perfil = perfilDoc.data();
    const dispositivo = dispositivoDoc.data();
    const secuencia = secuenciaDoc.data();
    if (!perfil || !Array.isArray(perfil.roles) ||
        !perfil.roles.some((r) => ['reclutador', 'investigadorPrincipal'].includes(r))) {
      throw new HttpsError('permission-denied', 'Su función no permite enrolar.');
    }
    if (!dispositivo || dispositivo.autor_uid !== uid ||
        dispositivo.institucion_codigo !== perfil.institucion_codigo) {
      throw new HttpsError('permission-denied', 'El aparato no pertenece a esta cuenta.');
    }
    const centroDoc = await tx.get(db.collection('instituciones')
        .doc(perfil.institucion_codigo));
    if (centroDoc.data()?.cei_aprobado !== true) {
      throw new HttpsError('failed-precondition',
          'El centro no tiene aprobación del CEI registrada.');
    }
    const consentimientoDoc = await tx.get(db.collection('estudios').doc('livere')
        .collection('configuracion').doc('consentimiento'));
    const consentimiento = consentimientoDoc.data();
    if (consentimiento?.aprobado !== true ||
        typeof consentimiento.version !== 'string' ||
        typeof consentimiento.codigo_cei !== 'string' ||
        !Array.isArray(consentimiento.parrafos) ||
        consentimiento.parrafos.length === 0 ||
        !Array.isArray(consentimiento.declaraciones) ||
        consentimiento.declaraciones.length === 0) {
      throw new HttpsError('failed-precondition',
          'El consentimiento aprobado no está configurado.');
    }
    if (!secuencia || typeof secuencia.codigo_binario !== 'string' ||
        !/^[01]+$/.test(secuencia.codigo_binario) ||
        !secuencia.etiqueta || !Number.isInteger(secuencia.siguiente) ||
        !Number.isInteger(secuencia.tamano_tramo) ||
        secuencia.tamano_tramo < 1) {
      throw new HttpsError('failed-precondition',
          'La secuencia aún no está preparada para el estudio.');
    }

    const anterior = tramoDoc.data();
    if (anterior) {
      if (anterior.etiqueta !== secuencia.etiqueta) {
        throw new HttpsError('failed-precondition',
            'El aparato conserva un tramo de otra secuencia.');
      }
      const asignadas = await tx.get(db.collection('asignaciones')
          .where('dispositivo_id', '==', dispositivoId));
      const posiciones = new Set(asignadas.docs
          .map((d) => d.data())
          .filter((d) => d.secuencia_etiqueta === anterior.etiqueta)
          .map((d) => d.posicion)
          .filter((p) => p >= anterior.desde && p < anterior.hasta));
      if (posiciones.size < anterior.hasta - anterior.desde) {
        return {
          desde: anterior.desde, hasta: anterior.hasta,
          consumidas: posiciones.size,
          etiqueta: anterior.etiqueta,
          codigo_binario: anterior.codigo_binario,
          asignado_en: anterior.asignado_en,
        };
      }
    }

    const nuevoTramo = siguienteTramo(secuencia);
    if (!nuevoTramo) {
      throw new HttpsError('failed-precondition',
          'La secuencia de aleatorización está agotada.');
    }
    const nuevo = {
      ...nuevoTramo,
      asignado_en: new Date().toISOString(),
    };
    tx.update(secuenciaRef, {siguiente: nuevo.hasta});
    tx.set(tramoRef, {...nuevo, autor_uid: uid,
      institucion_codigo: perfil.institucion_codigo});
    return nuevo;
  });
});
