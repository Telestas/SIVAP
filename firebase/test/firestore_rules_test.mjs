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
  setDoc,
  where,
  writeBatch,
} from 'firebase/firestore';

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
