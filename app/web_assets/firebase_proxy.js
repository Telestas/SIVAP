// Instalar antes de FlutterFire; solo la web publicada en SIVAP Pages lo usa.
(function () {
  const host = window.location.hostname;
  if (!host.endsWith('.pages.dev')) return;

  const servicios = {
    'identitytoolkit.googleapis.com': 'auth',
    'securetoken.googleapis.com': 'token',
  };
  const original = window.fetch.bind(window);
  window.fetch = function (entrada, opciones) {
    const valor = typeof entrada === 'string' ? entrada : entrada.url || String(entrada);
    let destino;
    try {
      destino = new URL(valor, window.location.href);
    } catch (_) {
      return original(entrada, opciones);
    }
    const servicio = destino.protocol === 'https:' ? servicios[destino.hostname] : null;
    if (!servicio || !destino.pathname.startsWith('/v1/')) {
      return original(entrada, opciones);
    }
    const local = window.location.origin + '/api/firebase/' + servicio
        + destino.pathname + destino.search;
    if (entrada instanceof Request) {
      return original(new Request(local, new Request(entrada, opciones)));
    }
    return original(local, opciones);
  };
})();
