import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';
import { runInNewContext } from 'node:vm';
import { proxyFirestore, proxyIdentidad } from '../functions/_lib/proxyFirebase.js';

const CLAVE = 'AIzaSyDDk4UqDn-wYhAjSnI4WR4N3K79NjhA8Tg';
const BASE = 'https://sivap.pages.dev';

test('la web Pages llama al proxy y Firebase Hosting conserva el acceso directo', async () => {
  const codigo = readFileSync(new URL('../app/web_assets/firebase_proxy.js', import.meta.url), 'utf8');
  for (const dominio of ['sivap.pages.dev', 'sivap-f5060.web.app']) {
    const llamadas = [];
    const ventana = {
      location: { hostname: dominio, origin: `https://${dominio}`, href: `https://${dominio}/` },
      fetch: async (url) => { llamadas.push(String(url)); return new Response('{}'); },
    };
    runInNewContext(codigo, { window: ventana, URL, Request });
    await ventana.fetch(`https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=${CLAVE}`);
    assert.equal(llamadas[0], dominio.endsWith('.pages.dev')
      ? `${BASE}/api/firebase/auth/v1/accounts:signInWithPassword?key=${CLAVE}`
      : `https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=${CLAVE}`);
  }
});

test('reenvía el acceso y la renovación sin alterar las credenciales', async () => {
  const anterior = globalThis.fetch;
  const llamadas = [];
  globalThis.fetch = async (destino, opciones) => {
    llamadas.push({ destino: String(destino), opciones });
    return new Response('{"idToken":"ficticio"}', {
      headers: { 'Content-Type': 'application/json' },
    });
  };
  try {
    const acceso = await proxyIdentidad(new Request(
      `${BASE}/api/firebase/auth/v1/accounts:signInWithPassword?key=${CLAVE}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: '{"email":"ficticio@example.invalid","password":"ficticia"}',
      }), 'auth');
    assert.equal(acceso.status, 200);
    assert.equal(acceso.headers.get('Cache-Control'), 'no-store');
    assert.equal(
      llamadas[0].destino,
      `https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=${CLAVE}`,
    );
    assert.equal(
      await new Response(llamadas[0].opciones.body).text(),
      '{"email":"ficticio@example.invalid","password":"ficticia"}',
    );

    const token = await proxyIdentidad(new Request(
      `${BASE}/api/firebase/token/v1/token?key=${CLAVE}`, {
        method: 'POST', body: 'grant_type=refresh_token&refresh_token=ficticio',
      }), 'token');
    assert.equal(token.status, 200);
    assert.equal(
      llamadas[1].destino,
      `https://securetoken.googleapis.com/v1/token?key=${CLAVE}`,
    );
  } finally {
    globalThis.fetch = anterior;
  }
});

test('no funciona como proxy abierto para otros proyectos o acciones', async () => {
  const rutas = [
    `${BASE}/api/firebase/auth/v1/accounts:signInWithPassword?key=ajena`,
    `${BASE}/api/firebase/auth/v1/accounts:accionAjena?key=${CLAVE}`,
    `${BASE}/api/firebase/token/v1/token?key=ajena`,
  ];
  for (const ruta of rutas) {
    const servicio = ruta.includes('/token/') ? 'token' : 'auth';
    const respuesta = await proxyIdentidad(
      new Request(ruta, { method: 'POST' }), servicio);
    assert.equal(respuesta.status, 404);
  }
  const firestore = await proxyFirestore(new Request(
    `${BASE}/v1/projects/otro/databases/(default)/documents/pacientes`));
  assert.equal(firestore.status, 404);
});

test('reenvía Firestore con el token de sesión y sin caché', async () => {
  const anterior = globalThis.fetch;
  let llamada;
  globalThis.fetch = async (destino, opciones) => {
    llamada = { destino: String(destino), opciones };
    return new Response('{"documents":[]}', {
      headers: { 'Content-Type': 'application/json' },
    });
  };
  try {
    const respuesta = await proxyFirestore(new Request(
      `${BASE}/v1/projects/sivap-f5060/databases/(default)/documents/perfiles`, {
        headers: { 'Authorization': 'Bearer token-ficticio' },
      }));
    assert.equal(respuesta.status, 200);
    assert.equal(respuesta.headers.get('Cache-Control'), 'no-store');
    assert.equal(llamada.opciones.headers.get('Authorization'),
      'Bearer token-ficticio');
    assert.equal(llamada.destino,
      'https://firestore.googleapis.com/v1/projects/sivap-f5060/databases/(default)/documents/perfiles');
  } finally {
    globalThis.fetch = anterior;
  }
});
