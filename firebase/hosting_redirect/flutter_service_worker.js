'use strict';

// Desactiva las copias antiguas del cliente Flutter en este dominio.
self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', (evento) => {
  evento.waitUntil((async () => {
    await self.registration.unregister();
    const claves = await caches.keys();
    await Promise.all(claves
      .filter((clave) => clave.startsWith('flutter-'))
      .map((clave) => caches.delete(clave)));
  })());
});
