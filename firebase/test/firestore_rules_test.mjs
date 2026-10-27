import { readFile } from 'node:fs/promises';
import { after, afterEach, before, test } from 'node:test';
import assert from 'node:assert/strict';

import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import {
  collection,
  doc,
  getDoc,
  getDocs,
  query,
  runTransaction,
  setDoc,
  where,
  writeBatch,
} from 'firebase/firestore';
import { serverTimestamp } from 'firebase/firestore';
import {prepararPreproduccion, reservar} from '../administrar.mjs';

const proyecto = 'sivap-reglas-prueba';
let entorno;

const campos = (institucion, autor) => ({
  institucion_codigo: institucion,
  autor_uid: autor,
});

async function sembrarPerfil(uid, roles, institucion = 'centro-demo') {
  await entorno.withSecurityRulesDisabled(async (contexto) => {
    await setDoc(doc(contexto.firestore(), 'investigadores', uid), {
      institucion_codigo: institucion,
      roles,
    });
    await setDoc(doc(contexto.firestore(), 'instituciones', institucion), {
      cei_aprobado: true,
    });
    await setDoc(doc(contexto.firestore(), 'estudios', 'livere',
      'configuracion', 'consentimiento'), {
      aprobado: true,
      version: 'prueba-1',
      codigo_cei: 'CEI-PRUEBA',
      vigente_desde: '2026-10-26',
      parrafos: ['Texto inventado para la prueba.'],
      declaraciones: ['Acepto para esta prueba.'],
    });
  });
}

before(async () => {
  entorno = await initializeTestEnvironment({
    projectId: proyecto,
    firestore: {
      rules: await readFile(new URL('../firestore.rules', import.meta.url), 'utf8'),
    },
  });
});

after(async () => entorno.cleanup());
afterEach(async () => entorno.clearFirestore());

test('nadie crea datos clínicos sin perfil aprobado', async () => {
  const db = entorno.authenticatedContext('sin-perfil').firestore();
  await assertFails(setDoc(doc(db, 'pacientes', 'p-1'), {
    ...campos('centro-demo', 'sin-perfil'),
    codigo: 'DEM-001',
  }));
});

test('el reclutador solo crea identidad y paciente de su institución', async () => {
  await sembrarPerfil('reclutador', ['reclutador']);
  const db = entorno.authenticatedContext('reclutador').firestore();

  const lote = writeBatch(db);
  lote.set(doc(db, 'identidades', 'p-1'), {
    ...campos('centro-demo', 'reclutador'),
    nombre: 'Paciente de demostración',
  });
  lote.set(doc(db, 'pacientes', 'p-1'), {
    ...campos('centro-demo', 'reclutador'),
    codigo: 'DEM-001',
  });
  await assertSucceeds(lote.commit());
  await assertFails(setDoc(doc(db, 'pacientes', 'p-otro-centro'), {
    ...campos('otro-centro', 'reclutador'),
    codigo: 'OTR-001',
  }));
});

test('los roles no se crean ni se elevan desde un cliente', async () => {
  await sembrarPerfil('reclutador', ['reclutador']);
  const db = entorno.authenticatedContext('reclutador').firestore();

  await assertFails(setDoc(doc(db, 'investigadores', 'reclutador'), {
    institucion_codigo: 'centro-demo',
    roles: ['investigadorPrincipal'],
  }));
});

test('una cuenta verificada solicita acceso sin obtener permisos clínicos', async () => {
  await sembrarPerfil('principal', ['investigadorPrincipal']);
  const db = entorno.authenticatedContext('nuevo', {
    email: 'nuevo@ejemplo.test', email_verified: true,
  }).firestore();
  const solicitud = doc(db, 'solicitudes_acceso', 'nuevo');
  await assertSucceeds(setDoc(solicitud, {
    correo: 'nuevo@ejemplo.test', nombre: 'Persona de prueba',
    institucion_codigo: 'centro-demo', estado: 'pendiente',
    solicitado_en: serverTimestamp(),
  }));
  await assertFails(setDoc(doc(db, 'investigadores', 'nuevo'), {
    nombre: 'Persona de prueba', roles: ['investigadorPrincipal'],
    institucion_codigo: 'centro-demo',
  }));
  await assertFails(setDoc(doc(db, 'pacientes', 'p-nuevo'), {
    ...campos('centro-demo', 'nuevo'), codigo: 'DEM-002',
  }));
  await assertFails(setDoc(solicitud, {
    correo: 'nuevo@ejemplo.test', nombre: 'Persona cambiada',
    institucion_codigo: 'centro-demo', estado: 'pendiente',
    solicitado_en: serverTimestamp(),
  }));
});

test('correo sin verificar y centro inexistente no pueden solicitar acceso', async () => {
  await sembrarPerfil('principal', ['investigadorPrincipal']);
  const datos = {
    correo: 'nuevo@ejemplo.test', nombre: 'Persona de prueba',
    institucion_codigo: 'centro-demo', estado: 'pendiente',
    solicitado_en: serverTimestamp(),
  };
  const sinVerificar = entorno.authenticatedContext('nuevo', {
    email: 'nuevo@ejemplo.test', email_verified: false,
  }).firestore();
  await assertFails(setDoc(doc(sinVerificar, 'solicitudes_acceso', 'nuevo'), datos));
  const verificado = entorno.authenticatedContext('nuevo', {
    email: 'nuevo@ejemplo.test', email_verified: true,
  }).firestore();
  await assertFails(setDoc(doc(verificado, 'solicitudes_acceso', 'nuevo'), {
    ...datos, institucion_codigo: 'centro-inexistente',
  }));
});

test('solo el principal del centro aprueba y crea un rol permitido en el mismo lote', async () => {
  await sembrarPerfil('principal', ['investigadorPrincipal']);
  await sembrarPerfil('otro-principal', ['investigadorPrincipal'], 'otro-centro');
  await sembrarPerfil('reclutador', ['reclutador']);
  await entorno.withSecurityRulesDisabled(async (contexto) => {
    await setDoc(doc(contexto.firestore(), 'solicitudes_acceso', 'nuevo'), {
      correo: 'nuevo@ejemplo.test', nombre: 'Persona de prueba',
      institucion_codigo: 'centro-demo', estado: 'pendiente',
    });
  });
  async function aprobar(uid, rol, autor) {
    const db = entorno.authenticatedContext(autor).firestore();
    const lote = writeBatch(db);
    lote.set(doc(db, 'investigadores', uid), {
      correo: 'nuevo@ejemplo.test', nombre: 'Persona de prueba',
      institucion_codigo: 'centro-demo', roles: [rol],
      aprobado_por: autor, aprobado_en: serverTimestamp(),
    });
    lote.update(doc(db, 'solicitudes_acceso', uid), {
      estado: 'aprobado', rol_aprobado: rol,
      aprobado_por: autor, aprobado_en: serverTimestamp(),
    });
    return lote.commit();
  }
  await assertFails(aprobar('nuevo', 'investigadorPrincipal', 'principal'));
  await assertFails(aprobar('nuevo', 'reclutador', 'reclutador'));
  await assertFails(aprobar('nuevo', 'reclutador', 'otro-principal'));
  const principalDb = entorno.authenticatedContext('principal').firestore();
  await assertSucceeds(getDocs(query(collection(principalDb, 'solicitudes_acceso'),
    where('institucion_codigo', '==', 'centro-demo'))));
  await assertFails(getDocs(collection(principalDb, 'solicitudes_acceso')));
  await assertSucceeds(aprobar('nuevo', 'reclutador', 'principal'));
  const db = entorno.authenticatedContext('nuevo').firestore();
  assert.equal((await getDoc(doc(db, 'investigadores', 'nuevo'))).data().roles[0],
    'reclutador');
});

test('un dispositivo queda ligado al investigador que lo registró', async () => {
  await sembrarPerfil('reclutador', ['reclutador']);
  const db = entorno.authenticatedContext('reclutador').firestore();
  await assertSucceeds(setDoc(doc(db, 'dispositivos', 'd-1'), {
    ...campos('centro-demo', 'reclutador'),
    etiqueta: 'Aparato de demostración',
  }));
});

test('el evaluador no puede leer una identidad', async () => {
  await sembrarPerfil('reclutador', ['reclutador']);
  await sembrarPerfil('evaluador', ['evaluadorDesenlaces']);
  await entorno.withSecurityRulesDisabled(async (contexto) => {
    await setDoc(doc(contexto.firestore(), 'identidades', 'p-1'), {
      ...campos('centro-demo', 'reclutador'),
      nombre: 'Paciente de demostración',
    });
  });

  await assertFails(getDoc(doc(
    entorno.authenticatedContext('evaluador').firestore(), 'identidades', 'p-1')));
});

test('el panel consulta la cohorte solo dentro de su institución', async () => {
  await sembrarPerfil('analista', ['analista']);
  await entorno.withSecurityRulesDisabled(async (contexto) => {
    const db = contexto.firestore();
    await setDoc(doc(db, 'pacientes', 'p-centro'), {
      ...campos('centro-demo', 'reclutador'),
      codigo: 'DEM-001',
    });
    await setDoc(doc(db, 'pacientes', 'p-otro'), {
      ...campos('otro-centro', 'otro-reclutador'),
      codigo: 'OTR-001',
    });
  });

  const db = entorno.authenticatedContext('analista').firestore();
  await assertSucceeds(getDocs(query(
    collection(db, 'pacientes'),
    where('institucion_codigo', '==', 'centro-demo'),
  )));
  await assertFails(getDocs(collection(db, 'pacientes')));
});

test('el evaluador no recibe la asignación y el analista sí', async () => {
  await sembrarPerfil('evaluador', ['evaluadorDesenlaces']);
  await sembrarPerfil('analista', ['analista']);
  await entorno.withSecurityRulesDisabled(async (contexto) => {
    await setDoc(doc(contexto.firestore(), 'asignaciones', 'p-1'), {
      ...campos('centro-demo', 'reclutador'),
      protocolo: 'a',
    });
  });

  await assertFails(getDoc(doc(
    entorno.authenticatedContext('evaluador').firestore(),
    'asignaciones',
    'p-1',
  )));
  await assertSucceeds(getDoc(doc(
    entorno.authenticatedContext('analista').firestore(),
    'asignaciones',
    'p-1',
  )));
});

test('la rama y la posición deben coincidir con el tramo del aparato', async () => {
  await sembrarPerfil('reclutador', ['reclutador']);
  await entorno.withSecurityRulesDisabled(async (contexto) => {
    await setDoc(doc(contexto.firestore(), 'tramos', 'aparato-1'), {
      desde: 26, hasta: 28, codigo_binario: '10',
      etiqueta: 'secuencia-1', autor_uid: 'reclutador',
      institucion_codigo: 'centro-demo',
    });
  });
  const asignacion = {
    ...campos('centro-demo', 'reclutador'),
    dispositivo_id: 'aparato-1', secuencia_etiqueta: 'secuencia-1',
    posicion: 26, protocolo: 'b',
  };
  const db = entorno.authenticatedContext('reclutador').firestore();
  async function escribir(id, posicion, protocolo) {
    const lote = writeBatch(db);
    lote.set(doc(db, 'asignaciones', id), {
      ...asignacion, posicion, protocolo,
    });
    lote.set(doc(db, 'posiciones', String(posicion)), {
      ...campos('centro-demo', 'reclutador'),
      paciente_id: id, posicion, secuencia_etiqueta: 'secuencia-1',
    });
    return lote.commit();
  }
  await assertSucceeds(escribir('p-1', 26, 'b'));
  await assertFails(escribir('p-2', 27, 'b'));
  await assertFails(escribir('p-3', 28, 'a'));
  await assertFails(escribir('p-4', 26, 'b'));
  await assertFails(setDoc(doc(db, 'tramos', 'aparato-2'), asignacion));
});

test('cada función solo crea sus tipos de evento', async () => {
  await sembrarPerfil('aplicador', ['aplicador']);
  await sembrarPerfil('evaluador', ['evaluadorDesenlaces']);
  const aplicador = entorno.authenticatedContext('aplicador').firestore();
  const evaluador = entorno.authenticatedContext('evaluador').firestore();

  await entorno.withSecurityRulesDisabled(async (contexto) => {
    const db = contexto.firestore();
    await setDoc(doc(db, 'pacientes', 'p-1'), {
      ...campos('centro-demo', 'reclutador'), codigo: 'DEM-001',
    });
    await setDoc(doc(db, 'consentimientos', 'c-1'), {
      ...campos('centro-demo', 'reclutador'), paciente_id: 'p-1',
    });
  });
  const vinculo = { paciente_id: 'p-1', consentimiento_id: 'c-1' };

  await assertSucceeds(setDoc(doc(aplicador, 'eventos', 'e-1'), {
    ...campos('centro-demo', 'aplicador'),
    ...vinculo,
    tipo: 'extubacion',
  }));
  await assertFails(setDoc(doc(aplicador, 'eventos', 'e-2'), {
    ...campos('centro-demo', 'aplicador'),
    ...vinculo,
    tipo: 'desenlaces',
  }));
  await assertSucceeds(setDoc(doc(evaluador, 'eventos', 'e-3'), {
    ...campos('centro-demo', 'evaluador'),
    ...vinculo,
    tipo: 'desenlaces',
  }));
});

test('sin aprobación del centro no se crea un paciente', async () => {
  await sembrarPerfil('reclutador', ['reclutador']);
  await entorno.withSecurityRulesDisabled(async (contexto) => {
    await setDoc(doc(contexto.firestore(), 'instituciones', 'centro-demo'), {
      cei_aprobado: false,
    });
  });
  const db = entorno.authenticatedContext('reclutador').firestore();
  await assertFails(setDoc(doc(db, 'pacientes', 'p-1'), {
    ...campos('centro-demo', 'reclutador'), codigo: 'DEM-001',
  }));
});

test('consentimiento exige versión aprobada, firma y texto archivado', async () => {
  await sembrarPerfil('reclutador', ['reclutador']);
  await entorno.withSecurityRulesDisabled(async (contexto) => {
    await setDoc(doc(contexto.firestore(), 'pacientes', 'p-1'), {
      ...campos('centro-demo', 'reclutador'), codigo: 'DEM-001',
    });
  });
  const db = entorno.authenticatedContext('reclutador').firestore();
  const consentimiento = {
    ...campos('centro-demo', 'reclutador'),
    paciente_id: 'p-1', version_documento: 'prueba-1',
    codigo_cei: 'CEI-PRUEBA', firma: { trazos: [{puntos: [{x: 0.5, y: 0.5}]}] },
    documento_firmado: {
      version: 'prueba-1', codigo_cei: 'CEI-PRUEBA',
      parrafos: ['Texto inventado para la prueba.'],
      declaraciones: ['Acepto para esta prueba.'],
    },
  };
  await assertSucceeds(setDoc(doc(db, 'consentimientos', 'c-1'), consentimiento));
  await assertFails(setDoc(doc(db, 'consentimientos', 'c-2'), {
    ...consentimiento, version_documento: 'otra-version',
  }));
  await assertFails(setDoc(doc(db, 'consentimientos', 'c-3'), {
    ...consentimiento, firma: { trazos: [] },
  }));
});

test('los registros enviados y la auditoría son inmutables', async () => {
  await sembrarPerfil('principal', ['investigadorPrincipal']);
  const db = entorno.authenticatedContext('principal').firestore();

  await assertSucceeds(setDoc(doc(db, 'auditoria', 'a-1'), {
    ...campos('centro-demo', 'principal'),
    entidad: 'evento', campo: 'valor',
    motivo: 'Corrección de demostración',
  }));
  await assertFails(setDoc(doc(db, 'auditoria', 'a-1'), {
    ...campos('centro-demo', 'principal'),
    entidad: 'evento', campo: 'valor',
    motivo: 'Cambio silencioso',
  }));
});

test('solo analista o principal registra una exportación', async () => {
  await sembrarPerfil('analista', ['analista']);
  await sembrarPerfil('reclutador', ['reclutador']);
  const entrada = {
    ...campos('centro-demo', 'analista'),
    entidad: 'exportacion', campo: 'archivo',
    valor_nuevo: 'sivap-clinico.xlsx', motivo: 'Descarga',
  };
  await assertSucceeds(setDoc(doc(
    entorno.authenticatedContext('analista').firestore(), 'auditoria', 'a-1'),
  entrada));
  await assertFails(setDoc(doc(
    entorno.authenticatedContext('reclutador').firestore(), 'auditoria', 'a-2'),
  {...entrada, autor_uid: 'reclutador'}));
});

async function recogerReserva(db, aparato) {
  const reserva = doc(db, 'reservas_tramos', 'principal');
  return runTransaction(db, async (tx) => {
    const datos = (await tx.get(reserva)).data();
    if (datos.dispositivo_id !== null) throw new Error('Reserva reclamada');
    tx.set(doc(db, 'tramos', aparato), datos.tramo);
    tx.update(reserva, {dispositivo_id: aparato});
  });
}

async function prepararSpark() {
  await sembrarPerfil('principal', ['investigadorPrincipal']);
  await entorno.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), 'estudios/livere/configuracion/consentimiento'),
      {aprobado: false}, {merge: true});
  });
  // El emulador 1.21 no serializa beginTransaction por REST en Java 25.
  // Se ejercitan las mismas operaciones administrativas con transacciones SDK.
  const admin = {
    escritura: (ruta, datos, campos) => ({ruta, datos, campos}),
    leer: async (ruta, tx) => {
      if (tx) return (await tx.tx.get(doc(tx.db, ruta))).data() || null;
      let datos;
      await entorno.withSecurityRulesDisabled(async (ctx) => {
        datos = (await getDoc(doc(ctx.firestore(), ruta))).data() || null;
      });
      return datos;
    },
    transaccion: (operacion) => entorno.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      return runTransaction(db, async (tx) => {
        const {writes, resultado} = await operacion({tx, db});
        for (const w of writes) tx.set(doc(db, w.ruta), w.datos, {merge: !!w.campos});
        return resultado;
      });
    }),
  };
  // El helper antiguo sembró un documento aprobado ficticio; aquí se prueba
  // explícitamente el entorno integrado con la aprobación real desactivada.
  await prepararPreproduccion(admin, 'centro-demo');
  await reservar(admin, 'principal');
  const db = entorno.authenticatedContext('principal').firestore();
  for (const id of ['aparato-1', 'aparato-2']) {
    await setDoc(doc(db, 'dispositivos', id), campos('centro-demo', 'principal'));
  }
  return {admin, db};
}

test('Spark reserva en CLI y solo un teléfono reclama el tramo sin modificarlo', async () => {
  const {admin, db} = await prepararSpark();
  const inicial = await admin.leer('aleatorizacion/activa');
  await reservar(admin, 'principal');
  assert.equal((await admin.leer('aleatorizacion/activa')).siguiente, inicial.siguiente);
  const resultados = await Promise.allSettled([
    recogerReserva(db, 'aparato-1'), recogerReserva(db, 'aparato-2'),
  ]);
  assert.equal(resultados.filter((r) => r.status === 'fulfilled').length, 1);
  const reserva = await admin.leer('reservas_tramos/principal');
  assert.deepEqual(await admin.leer(`tramos/${reserva.dispositivo_id}`), reserva.tramo);
  await assertFails(setDoc(doc(db, 'tramos', reserva.dispositivo_id), {
    ...reserva.tramo, codigo_binario: '0'.repeat(50),
  }));
  await assertFails(getDoc(doc(entorno.authenticatedContext('intruso').firestore(),
    'reservas_tramos', 'principal')));
  await assertFails(getDoc(doc(db, 'aleatorizacion', 'activa')));
});

test('preproducción sincroniza ficha, asignación, firma y evento; producción exige aprobación real', async () => {
  const {admin, db} = await prepararSpark();
  await entorno.withSecurityRulesDisabled(async (contexto) => {
    await setDoc(doc(contexto.firestore(), 'instituciones', 'centro-demo'), {
      cei_aprobado: false, habilitado_pruebas: true,
    });
  });
  await recogerReserva(db, 'aparato-1');
  // El primer envío consulta un acuse que todavía no existe.
  await assertSucceeds(getDoc(doc(db, 'lotes', 'primer-lote')));
  const tramo = await admin.leer('tramos/aparato-1');
  const consentimiento = await admin.leer('estudios/livere/configuracion/consentimiento');
  const comunes = {...campos('centro-demo', 'principal'), dispositivo_id: 'aparato-1'};
  const lote = writeBatch(db);
  lote.set(doc(db, 'pacientes', 'paciente-ficticio'), {...comunes, codigo: 'PRUEBA-001'});
  lote.set(doc(db, 'identidades', 'paciente-ficticio'), {...comunes, nombre: 'Paciente ficticio'});
  lote.set(doc(db, 'asignaciones', 'paciente-ficticio'), {
    ...comunes, posicion: tramo.desde, secuencia_etiqueta: tramo.etiqueta,
    protocolo: tramo.codigo_binario[0] === '1' ? 'b' : 'a',
  });
  lote.set(doc(db, 'posiciones', String(tramo.desde)), {
    ...comunes, posicion: tramo.desde, paciente_id: 'paciente-ficticio',
  });
  lote.set(doc(db, 'consentimientos', 'firma-ficticia'), {
    ...comunes, paciente_id: 'paciente-ficticio',
    version_documento: consentimiento.version, codigo_cei: consentimiento.codigo_cei,
    documento_firmado: consentimiento, firma: {trazos: [{puntos: [{x: 0.1, y: 0.2}]}]},
  });
  lote.set(doc(db, 'eventos', 'evento-ficticio'), {
    ...comunes, paciente_id: 'paciente-ficticio', consentimiento_id: 'firma-ficticia',
    tipo: 'cribado',
  });
  lote.set(doc(db, 'lotes', 'primer-lote'), comunes);
  await assertSucceeds(lote.commit());
  await assertSucceeds(getDoc(doc(db, 'lotes', 'primer-lote')));
  await assertFails(getDoc(doc(entorno.authenticatedContext('intruso').firestore(),
    'lotes', 'primer-lote')));
  await admin.transaccion(async () => ({writes: [
    admin.escritura('estudios/livere', {entorno: 'produccion'}, ['entorno']),
  ]}));
  await assertFails(setDoc(doc(db, 'pacientes', 'otro'), {...comunes, codigo: 'PRUEBA-002'}));
  await assertFails(setDoc(doc(db, 'estudios', 'livere'), {
    entorno: 'preproduccion', captura_habilitada: true,
  }));
});

test('dos reservas administrativas concurrentes nunca comparten posiciones', async () => {
  const {admin} = await prepararSpark();
  await admin.transaccion(async () => ({writes: ['otra-cuenta', 'tercera-cuenta']
    .map((uid) => admin.escritura(`investigadores/${uid}`, {
      roles: ['reclutador'], institucion_codigo: 'centro-demo',
    }))}));
  await Promise.all([reservar(admin, 'otra-cuenta'), reservar(admin, 'tercera-cuenta')]);
  const a = (await admin.leer('reservas_tramos/otra-cuenta')).tramo;
  const b = (await admin.leer('reservas_tramos/tercera-cuenta')).tramo;
  assert.ok(a.hasta <= b.desde || b.hasta <= a.desde);
});
