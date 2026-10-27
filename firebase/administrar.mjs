import {createRequire} from 'node:module';
import {randomBytes, randomUUID} from 'node:crypto';
import {pathToFileURL} from 'node:url';
import {siguienteTramo} from './functions/tramo.mjs';

const require = createRequire(import.meta.url);

function codificar(valor) {
  if (valor === null) return {nullValue: null};
  if (typeof valor === 'boolean') return {booleanValue: valor};
  if (typeof valor === 'number') return {integerValue: String(valor)};
  if (typeof valor === 'string') return {stringValue: valor};
  if (Array.isArray(valor)) return {arrayValue: {values: valor.map(codificar)}};
  return {mapValue: {fields: Object.fromEntries(
    Object.entries(valor).map(([k, v]) => [k, codificar(v)]))}};
}
function decodificar(valor) {
  if ('nullValue' in valor) return null;
  if ('booleanValue' in valor) return valor.booleanValue;
  if ('integerValue' in valor) return Number(valor.integerValue);
  if ('stringValue' in valor) return valor.stringValue;
  if ('arrayValue' in valor) return (valor.arrayValue.values || []).map(decodificar);
  return Object.fromEntries(Object.entries(valor.mapValue?.fields || {})
    .map(([k, v]) => [k, decodificar(v)]));
}

/** Credencial del operador Firebase local; nunca se guarda en este repositorio. */
async function tokenOperador() {
  const {configstore} = require('firebase-tools/lib/configstore');
  const {getAccessToken} = require('firebase-tools/lib/auth');
  const tokens = await getAccessToken(configstore.get('tokens.refresh_token'), []);
  return tokens.access_token;
}

export class AdministracionFirestore {
  constructor(proyecto) {
    this.raiz = `projects/${proyecto}/databases/(default)/documents`;
    this.base = process.env.FIRESTORE_EMULATOR_HOST
      ? `http://${process.env.FIRESTORE_EMULATOR_HOST}/v1`
      : 'https://firestore.googleapis.com/v1';
    this.operador = process.env.FIRESTORE_EMULATOR_HOST ? 'emulador' :
      require('firebase-tools/lib/configstore').configstore.get('user.email') || 'cli-local';
  }
  async pedir(ruta, metodo = 'GET', cuerpo) {
    const token = process.env.FIRESTORE_EMULATOR_HOST ? 'owner' : await tokenOperador();
    const r = await fetch(`${this.base}/${ruta}`, {
      method: metodo,
      headers: {Authorization: `Bearer ${token}`, 'Content-Type': 'application/json'},
      body: cuerpo === undefined ? undefined : JSON.stringify(cuerpo),
      signal: AbortSignal.timeout(30000),
    });
    if (r.status === 404) return null;
    const datos = await r.json();
    if (!r.ok) throw new Error(`Firestore ${r.status}: ${datos.error?.status || 'error'}`);
    return datos;
  }
  async leer(ruta, tx) {
    const doc = await this.pedir(`${this.raiz}/${ruta}${tx ? `?transaction=${encodeURIComponent(tx)}` : ''}`);
    return doc ? Object.fromEntries(Object.entries(doc.fields || {})
      .map(([k, v]) => [k, decodificar(v)])) : null;
  }
  escritura(ruta, datos, campos) {
    return {update: {name: `${this.raiz}/${ruta}`,
      fields: Object.fromEntries(Object.entries(datos).map(([k, v]) => [k, codificar(v)]))},
    ...(campos ? {updateMask: {fieldPaths: campos}} : {})};
  }
  async transaccion(operacion) {
    for (let intento = 0; intento < 5; intento++) {
      const {transaction} = await this.pedir(`${this.raiz}:beginTransaction`, 'POST', {});
      try {
        const {writes, resultado} = await operacion(transaction);
        await this.pedir(`${this.raiz}:commit`, 'POST', {transaction, writes});
        return resultado;
      } catch (error) {
        await this.pedir(`${this.raiz}:rollback`, 'POST', {transaction}).catch(() => {});
        if (!error.message.includes('ABORTED') || intento === 4) throw error;
      }
    }
  }
}

export async function prepararPreproduccion(db, centro) {
  // La operación no limpia datos ni reemplaza una secuencia existente.
  return db.transaccion(async (tx) => {
    const institucion = await db.leer(`instituciones/${centro}`, tx);
    const estudio = await db.leer('estudios/livere', tx);
    const secuencia = await db.leer('aleatorizacion/activa', tx);
    const consentimiento = await db.leer('estudios/livere/configuracion/consentimiento', tx);
    if (!institucion) throw new Error('El centro no existe.');
    if ((estudio?.entorno && estudio.entorno !== 'preproduccion') ||
        (secuencia && !secuencia.etiqueta?.startsWith('preproduccion-')) ||
        (consentimiento?.aprobado === true && estudio?.entorno !== 'preproduccion')) {
      throw new Error('El proyecto contiene configuración de producción; no se cambia automáticamente.');
    }
    const ahora = new Date().toISOString();
    const writes = [
      db.escritura('estudios/livere', {entorno: 'preproduccion', captura_habilitada: true,
        entrega_tramos: 'reservas'}, ['entorno', 'captura_habilitada', 'entrega_tramos']),
      db.escritura(`instituciones/${centro}`, {habilitado_pruebas: true}, ['habilitado_pruebas']),
      db.escritura('estudios/livere/configuracion/consentimiento', {
        aprobado: false, tipo: 'prueba', habilitado: true,
        version: 'preproduccion-v1', codigo_cei: 'PRUEBA-SIN-VALIDEZ-CEI',
        vigente_desde: ahora.slice(0, 10),
        parrafos: ['Documento ficticio para probar el funcionamiento de SIVAP.',
          'Esta sesión permite comprobar registro, firma, asignación y sincronización. Use únicamente pacientes ficticios.'],
        declaraciones: ['Confirmo que este paciente es ficticio.',
          'Registro esta firma exclusivamente para probar el flujo de la aplicación.'],
      }),
      db.escritura(`auditoria_administrativa/${randomUUID()}`, {
        accion: 'preparar_preproduccion', institucion_codigo: centro, ocurrido_en: ahora,
        operador: db.operador || 'operador-prueba',
      }),
    ];
    if (!secuencia) {
      writes.push(db.escritura('aleatorizacion/activa', {
        etiqueta: `preproduccion-${randomUUID()}`, siguiente: 1, tamano_tramo: 50,
        codigo_binario: [...randomBytes(400)].map((b) => String(b & 1)).join(''),
        generada_en: ahora, entorno: 'preproduccion',
      }));
    }
    return {writes, resultado: {entorno: 'preproduccion', captura_habilitada: true}};
  });
}

export async function reservar(db, uid) {
  return db.transaccion(async (tx) => {
    const perfil = await db.leer(`investigadores/${uid}`, tx);
    const secuencia = await db.leer('aleatorizacion/activa', tx);
    const anterior = await db.leer(`reservas_tramos/${uid}`, tx);
    if (!perfil?.roles?.some((r) => ['reclutador', 'investigadorPrincipal'].includes(r))) {
      throw new Error('La cuenta no tiene una función que permita enrolar.');
    }
    if (anterior?.dispositivo_id === null) {
      return {writes: [], resultado: {reserva: 'ya_preparada'}};
    }
    if (!secuencia) throw new Error('No hay una secuencia cargada.');
    if (!/^[01]+$/.test(secuencia.codigo_binario || '') ||
        !Number.isInteger(secuencia.siguiente) ||
        !Number.isInteger(secuencia.tamano_tramo) || secuencia.tamano_tramo < 1) {
      throw new Error('La secuencia cargada no es válida.');
    }
    const tramo = siguienteTramo(secuencia);
    if (!tramo) throw new Error('La secuencia se agotó.');
    const ahora = new Date().toISOString();
    const datos = {...tramo, asignado_en: ahora, autor_uid: uid,
      institucion_codigo: perfil.institucion_codigo};
    return {writes: [
      db.escritura('aleatorizacion/activa', {siguiente: tramo.hasta}, ['siguiente']),
      db.escritura(`reservas_tramos/${uid}`, {tramo: datos, dispositivo_id: null}),
      db.escritura(`auditoria_administrativa/${randomUUID()}`, {
        accion: 'reservar_tramo', autor_uid: uid, ocurrido_en: ahora,
        operador: db.operador || 'operador-prueba',
        desde: tramo.desde, hasta: tramo.hasta, etiqueta: tramo.etiqueta,
      }),
    ], resultado: {reserva: 'preparada', posiciones: tramo.hasta - tramo.desde}};
  });
}

async function main() {
  const [accion, ...args] = process.argv.slice(2);
  const opciones = Object.fromEntries(Array.from({length: args.length / 2},
    (_, i) => [args[i * 2], args[i * 2 + 1]]));
  const proyecto = opciones['--proyecto'];
  if (!proyecto || !['preparar-preproduccion', 'reservar'].includes(accion)) {
    throw new Error('Uso: node firebase/administrar.mjs preparar-preproduccion --proyecto ID --centro CODIGO | reservar --proyecto ID --uid UID');
  }
  const db = new AdministracionFirestore(proyecto);
  if (accion === 'preparar-preproduccion') {
    if (!opciones['--centro']) throw new Error('Falta --centro.');
    console.log(JSON.stringify(await prepararPreproduccion(db, opciones['--centro'])));
  } else {
    if (!opciones['--uid']) throw new Error('Falta --uid.');
    console.log(JSON.stringify(await reservar(db, opciones['--uid'])));
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main().catch((error) => {console.error(error.message); process.exitCode = 1;});
}
