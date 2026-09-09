import { readFile } from 'node:fs/promises';
import { after, afterEach, before, test } from 'node:test';
import assert from 'node:assert/strict';

import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import { doc, getDoc, setDoc } from 'firebase/firestore';

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

  await assertSucceeds(setDoc(doc(db, 'identidades', 'p-1'), {
    ...campos('centro-demo', 'reclutador'),
    nombre: 'Paciente de demostración',
  }));
  await assertSucceeds(setDoc(doc(db, 'pacientes', 'p-1'), {
    ...campos('centro-demo', 'reclutador'),
    codigo: 'DEM-001',
  }));
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

test('cada función solo crea sus tipos de evento', async () => {
  await sembrarPerfil('aplicador', ['aplicador']);
  await sembrarPerfil('evaluador', ['evaluadorDesenlaces']);
  const aplicador = entorno.authenticatedContext('aplicador').firestore();
  const evaluador = entorno.authenticatedContext('evaluador').firestore();

  await assertSucceeds(setDoc(doc(aplicador, 'eventos', 'e-1'), {
    ...campos('centro-demo', 'aplicador'),
    tipo: 'extubacion',
  }));
  await assertFails(setDoc(doc(aplicador, 'eventos', 'e-2'), {
    ...campos('centro-demo', 'aplicador'),
    tipo: 'desenlaces',
  }));
  await assertSucceeds(setDoc(doc(evaluador, 'eventos', 'e-3'), {
    ...campos('centro-demo', 'evaluador'),
    tipo: 'desenlaces',
  }));
});

test('los registros enviados y la auditoría son inmutables', async () => {
  await sembrarPerfil('principal', ['investigadorPrincipal']);
  const db = entorno.authenticatedContext('principal').firestore();

  await assertSucceeds(setDoc(doc(db, 'auditoria', 'a-1'), {
    ...campos('centro-demo', 'principal'),
    motivo: 'Corrección de demostración',
  }));
  await assertFails(setDoc(doc(db, 'auditoria', 'a-1'), {
    ...campos('centro-demo', 'principal'),
    motivo: 'Cambio silencioso',
  }));
});
