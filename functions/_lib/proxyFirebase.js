// Transporte público: Firebase verifica credenciales, roles y reglas.
const CLAVE_WEB = 'AIzaSyDDk4UqDn-wYhAjSnI4WR4N3K79NjhA8Tg';
const PROYECTO = 'sivap-f5060';

const SERVICIOS = {
  auth: 'https://identitytoolkit.googleapis.com',
  token: 'https://securetoken.googleapis.com',
};

const CABECERAS_PETICION = [
  'Authorization',
  'Content-Type',
  'X-Client-Version',
  'X-Firebase-AppCheck',
  'X-Firebase-Client',
  'X-Firebase-GMPID',
  'X-Firebase-Locale',
  'X-Goog-Api-Client',
];

const respuestaError = (mensaje, estado) =>
  new Response(mensaje, {
    status: estado,
    headers: { 'Cache-Control': 'no-store', 'Content-Type': 'text/plain; charset=utf-8' },
  });

const reenviar = async (peticion, destino) => {
  const cabeceras = new Headers();
  for (const nombre of CABECERAS_PETICION) {
    const valor = peticion.headers.get(nombre);
    if (valor) cabeceras.set(nombre, valor);
  }
  try {
    const respuesta = await fetch(destino, {
      method: peticion.method,
      headers: cabeceras,
      body: ['GET', 'HEAD'].includes(peticion.method) ? undefined : peticion.body,
      redirect: 'manual',
    });
    const salida = new Headers({ 'Cache-Control': 'no-store' });
    for (const nombre of ['Content-Type', 'X-HTTP-Session-Id']) {
      const valor = respuesta.headers.get(nombre);
      if (valor) salida.set(nombre, valor);
    }
    return new Response(respuesta.body, { status: respuesta.status, headers: salida });
  } catch {
    return respuestaError('Firebase no responde.', 502);
  }
};

/** Rutas de Auth y renovación para la clave web de este proyecto. */
export const proxyIdentidad = async (peticion, servicio) => {
  const url = new URL(peticion.url);
  const ruta = url.pathname.slice(`/api/firebase/${servicio}`.length);
  const acciones = new Set([
    'signInWithPassword', 'signUp', 'lookup', 'sendOobCode',
    'resetPassword', 'update', 'delete',
  ]);
  const authPermitida = servicio === 'auth'
    && ruta.startsWith('/v1/accounts:')
    && acciones.has(ruta.slice('/v1/accounts:'.length))
    && peticion.method === 'POST';
  const tokenPermitido = servicio === 'token'
    && ruta === '/v1/token'
    && peticion.method === 'POST';
  if ((!authPermitida && !tokenPermitido)
      || url.searchParams.get('key') !== CLAVE_WEB) {
    return respuestaError('Ruta no permitida.', 404);
  }
  return reenviar(peticion, new URL(ruta + url.search, SERVICIOS[servicio]));
};

/** Rutas de documentos y canales únicamente de SIVAP. */
export const proxyFirestore = async (peticion) => {
  const url = new URL(peticion.url);
  const documentos = `/v1/projects/${PROYECTO}/databases/(default)/documents`;
  const esDocumento = url.pathname === documentos
    || url.pathname.startsWith(`${documentos}/`)
    || url.pathname.startsWith(`${documentos}:`);
  const esCanal = /^\/google\.firestore\.v1\.Firestore\/(Listen|Write)\/channel$/.test(url.pathname)
    && url.searchParams.get('database') === `projects/${PROYECTO}/databases/(default)`;
  if ((!esDocumento && !esCanal)
      || !['GET', 'POST', 'PATCH', 'DELETE'].includes(peticion.method)) {
    return respuestaError('Ruta no permitida.', 404);
  }
  return reenviar(peticion,
    new URL(url.pathname + url.search, 'https://firestore.googleapis.com'));
};
