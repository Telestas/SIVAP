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

const rolesValidos = new Set([
  'reclutador', 'aplicador', 'evaluadorDesenlaces', 'analista',
  'investigadorPrincipal',
]);

function codigoCentro(codigo) {
  if (typeof codigo !== 'string' || !/^[A-Za-z0-9][A-Za-z0-9_-]{1,39}$/.test(codigo)) {
    throw new Error('El código del centro debe tener 2–40 letras, números, guiones o guiones bajos.');
  }
  return codigo;
}

function nombreVisible(nombre) {
  const limpio = nombre?.trim();
  if (!limpio || limpio.length < 2 || limpio.length > 120) {
    throw new Error('El nombre debe tener entre 2 y 120 caracteres.');
  }
  return limpio;
}

function verificarCuenta(cuenta) {
  if (!cuenta?.uid || !cuenta.email || cuenta.emailVerified !== true) {
    throw new Error('La cuenta de Firebase Authentication debe existir y tener el correo verificado.');
  }
}

function auditoria(db, accion, datos) {
  return db.escritura(`auditoria_administrativa/${randomUUID()}`, {
    accion, ...datos, operador: db.operador || 'operador-local',
    ocurrido_en: new Date().toISOString(),
  });
}

/** Crea un centro deshabilitado: la aprobación clínica se registra aparte. */
export async function crearCentro(db, codigo, nombre) {
  codigo = codigoCentro(codigo);
  nombre = nombreVisible(nombre);
  return db.transaccion(async (tx) => {
    if (await db.leer(`instituciones/${codigo}`, tx)) {
      throw new Error('El código del centro ya existe. Use renombrar-centro para cambiar el nombre.');
    }
    return {writes: [
      db.escritura(`instituciones/${codigo}`, {
        nombre, cei_aprobado: false, habilitado_pruebas: false,
      }),
      auditoria(db, 'crear_centro', {institucion_codigo: codigo}),
    ], resultado: {centro: codigo, captura_habilitada: false}};
  });
}

/** Cambia únicamente el nombre visible; el código estable no se modifica. */
export async function renombrarCentro(db, codigo, nombre) {
  codigo = codigoCentro(codigo);
  nombre = nombreVisible(nombre);
  return db.transaccion(async (tx) => {
    const centro = await db.leer(`instituciones/${codigo}`, tx);
    if (!centro) throw new Error('El centro no existe.');
    if (centro.nombre === nombre) return {writes: [], resultado: {centro: codigo, sin_cambios: true}};
    return {writes: [
      db.escritura(`instituciones/${codigo}`, {nombre}, ['nombre']),
      auditoria(db, 'renombrar_centro', {institucion_codigo: codigo}),
    ], resultado: {centro: codigo, nombre}};
  });
}

/** Aprovisiona un principal desde una cuenta verificada, incluso si solicitó acceso. */
export async function asignarPrincipal(db, cuenta, codigo, nombre) {
  verificarCuenta(cuenta);
  codigo = codigoCentro(codigo);
  return db.transaccion(async (tx) => {
    const centro = await db.leer(`instituciones/${codigo}`, tx);
    if (!centro) throw new Error('El centro no existe. Créelo primero.');
    const rutaPerfil = `investigadores/${cuenta.uid}`;
    const rutaSolicitud = `solicitudes_acceso/${cuenta.uid}`;
    const perfil = await db.leer(rutaPerfil, tx);
    const solicitud = await db.leer(rutaSolicitud, tx);
    if (perfil && perfil.institucion_codigo !== codigo) {
      throw new Error('El perfil ya pertenece a otro centro.');
    }
    if (perfil?.correo && perfil.correo.toLowerCase() !== cuenta.email.toLowerCase()) {
      throw new Error('El correo del perfil no coincide con Authentication.');
    }
    if (solicitud && (solicitud.institucion_codigo !== codigo ||
        solicitud.correo?.toLowerCase() !== cuenta.email.toLowerCase())) {
      throw new Error('La solicitud pendiente corresponde a otro centro o correo.');
    }
    if (perfil?.roles?.includes('investigadorPrincipal')) {
      return {writes: [], resultado: {uid: cuenta.uid, rol: 'investigadorPrincipal', sin_cambios: true}};
    }
    const nombrePerfil = nombreVisible(perfil?.nombre || solicitud?.nombre || nombre || cuenta.displayName);
    const ahora = new Date().toISOString();
    const writes = [
      perfil
        ? db.escritura(rutaPerfil, {roles: ['investigadorPrincipal']}, ['roles'])
        : db.escritura(rutaPerfil, {
          nombre: nombrePerfil, correo: cuenta.email, institucion_codigo: codigo,
          roles: ['investigadorPrincipal'], aprobado_por: db.operador,
          aprobado_en: ahora,
        }),
      auditoria(db, 'asignar_principal', {
        uid: cuenta.uid, institucion_codigo: codigo,
        roles_anteriores: perfil?.roles || [], roles_nuevos: ['investigadorPrincipal'],
      }),
    ];
    if (solicitud?.estado === 'pendiente') {
      writes.push(db.escritura(rutaSolicitud, {
        estado: 'aprobado', rol_aprobado: 'investigadorPrincipal',
        aprobado_por: db.operador, aprobado_en: ahora,
      }, ['estado', 'rol_aprobado', 'aprobado_por', 'aprobado_en']));
    }
    return {writes, resultado: {uid: cuenta.uid, rol: 'investigadorPrincipal', centro: codigo}};
  });
}

/** Reemplaza los roles de un perfil aprobado, dejando rastro administrativo. */
export async function cambiarRoles(db, cuenta, roles) {
  verificarCuenta(cuenta);
  if (!Array.isArray(roles) || roles.length === 0 ||
      roles.some((rol) => !rolesValidos.has(rol)) || new Set(roles).size !== roles.length) {
    throw new Error('Indique roles válidos, sin duplicados, separados por comas.');
  }
  if (roles.includes('investigadorPrincipal')) {
    throw new Error('Use asignar-principal para conceder el rol principal.');
  }
  if (roles.includes('aplicador') && roles.includes('evaluadorDesenlaces')) {
    throw new Error('Aplicador y evaluador de desenlaces no pueden acumularse: rompe el cegamiento.');
  }
  return db.transaccion(async (tx) => {
    const ruta = `investigadores/${cuenta.uid}`;
    const perfil = await db.leer(ruta, tx);
    if (!perfil) throw new Error('La cuenta no tiene un perfil aprobado.');
    if (perfil.correo && perfil.correo.toLowerCase() !== cuenta.email.toLowerCase()) {
      throw new Error('El correo del perfil no coincide con Authentication.');
    }
    if (perfil.roles?.includes('investigadorPrincipal')) {
      throw new Error('El rol principal se cambia mediante el procedimiento administrativo del estudio.');
    }
    if (JSON.stringify(perfil.roles) === JSON.stringify(roles)) {
      return {writes: [], resultado: {uid: cuenta.uid, roles, sin_cambios: true}};
    }
    return {writes: [
      db.escritura(ruta, {roles}, ['roles']),
      auditoria(db, 'cambiar_roles', {
        uid: cuenta.uid, institucion_codigo: perfil.institucion_codigo,
        roles_anteriores: perfil.roles || [], roles_nuevos: roles,
      }),
    ], resultado: {uid: cuenta.uid, roles}};
  });
}

async function main() {
  const [accion, ...args] = process.argv.slice(2);
  const opciones = Object.fromEntries(Array.from({length: args.length / 2},
    (_, i) => [args[i * 2], args[i * 2 + 1]]));
  const proyecto = opciones['--proyecto'];
  if (!proyecto || ![
    'preparar-preproduccion', 'reservar', 'crear-centro', 'renombrar-centro',
    'asignar-principal', 'cambiar-roles',
  ].includes(accion)) {
    throw new Error('Uso: node firebase/administrar.mjs ACCION --proyecto ID [--centro CODIGO --nombre NOMBRE | --correo EMAIL --roles ROL1,ROL2]');
  }
  const db = new AdministracionFirestore(proyecto);
  if (accion === 'preparar-preproduccion') {
    if (!opciones['--centro']) throw new Error('Falta --centro.');
    console.log(JSON.stringify(await prepararPreproduccion(db, opciones['--centro'])));
  } else if (accion === 'reservar') {
    if (!opciones['--uid']) throw new Error('Falta --uid.');
    console.log(JSON.stringify(await reservar(db, opciones['--uid'])));
  } else if (accion === 'crear-centro' || accion === 'renombrar-centro') {
    if (!opciones['--centro'] || !opciones['--nombre']) {
      throw new Error('Faltan --centro y --nombre.');
    }
    const operacion = accion === 'crear-centro' ? crearCentro : renombrarCentro;
    console.log(JSON.stringify(await operacion(db, opciones['--centro'], opciones['--nombre'])));
  } else {
    if (!opciones['--correo']) throw new Error('Falta --correo.');
    const {findUser} = require('firebase-tools/lib/gcp/auth');
    const cuenta = await findUser(proyecto, opciones['--correo'].trim());
    if (accion === 'asignar-principal') {
      if (!opciones['--centro']) throw new Error('Falta --centro.');
      console.log(JSON.stringify(await asignarPrincipal(
        db, cuenta, opciones['--centro'], opciones['--nombre'])));
    } else {
      if (!opciones['--roles']) throw new Error('Falta --roles.');
      console.log(JSON.stringify(await cambiarRoles(
        db, cuenta, opciones['--roles'].split(',').map((r) => r.trim()))));
    }
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main().catch((error) => {console.error(error.message); process.exitCode = 1;});
}
