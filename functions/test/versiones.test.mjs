import assert from 'node:assert/strict';
import {test} from 'node:test';
import {onRequestGet} from '../api/versiones.js';

test('identifica SIVAP ante GitHub aunque el cliente no envíe User-Agent', async () => {
  const anterior = globalThis.fetch;
  globalThis.fetch = async (url, opciones) => {
    assert.match(url, /^https:\/\/api\.github\.com\//);
    const cabeceras = new Headers(opciones.headers);
    if (!cabeceras.get('User-Agent')) return new Response(null, {status: 403});
    assert.equal(cabeceras.get('User-Agent'), 'SIVAP-versiones');
    return Response.json([]);
  };
  try {
    const respuesta = await onRequestGet({
      request: new Request('https://sivap.pages.dev/api/versiones'),
    });
    assert.equal(respuesta.status, 200);
    assert.deepEqual(await respuesta.json(), []);
  } finally {
    globalThis.fetch = anterior;
  }
});

test('publica solo metadatos de APK necesarios para la descarga', async () => {
  const anterior = globalThis.fetch;
  globalThis.fetch = async () => Response.json([{
    tag_name: 'v0.2.10', published_at: '2026-10-28T00:00:00Z',
    body: 'Huella', draft: false,
    assets: [
      {name: 'sivap-0.2.10-arm64.apk', size: 24, browser_download_url: 'https://github.com/apk', secreto: 'no'},
      {name: 'registro.txt', size: 1, browser_download_url: 'https://github.com/txt'},
    ],
  }]);
  try {
    const respuesta = await onRequestGet();
    assert.equal(respuesta.status, 200);
    const versiones = await respuesta.json();
    assert.equal(versiones.length, 1);
    assert.deepEqual(versiones[0].assets, [{
      name: 'sivap-0.2.10-arm64.apk', size: 24,
      browser_download_url: 'https://github.com/apk',
    }]);
  } finally {
    globalThis.fetch = anterior;
  }
});

test('conserva una respuesta reciente para no agotar GitHub', async () => {
  const anteriorFetch = globalThis.fetch;
  const anteriorCaches = globalThis.caches;
  let llamadas = 0;
  const almacen = new Map();
  globalThis.fetch = async () => {
    llamadas++;
    return Response.json([]);
  };
  globalThis.caches = {default: {
    match: async (clave) => almacen.get(clave.url),
    put: async (clave, valor) => almacen.set(clave.url, valor),
  }};
  const contexto = {
    request: new Request('https://sivap.pages.dev/api/versiones'),
    waitUntil: (promesa) => promesa,
  };
  try {
    await onRequestGet(contexto);
    const respuesta = await onRequestGet(contexto);
    assert.equal(respuesta.status, 200);
    assert.equal(llamadas, 1);
  } finally {
    globalThis.fetch = anteriorFetch;
    globalThis.caches = anteriorCaches;
  }
});
