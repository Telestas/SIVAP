const URL_VERSIONES =
  'https://api.github.com/repos/Telestas/SIVAP/releases?per_page=20';

/** Versiones públicas para la página de descarga y la app móvil. */
export const onRequestGet = async (contexto = {}) => {
  const cache = typeof caches === 'undefined' ? null : caches.default;
  const clave = new Request(
    contexto.request?.url ?? 'https://sivap.pages.dev/api/versiones',
  );
  const guardada = await cache?.match(clave);
  if (guardada) return guardada;

  try {
    const respuesta = await fetch(URL_VERSIONES, {
      headers: {
        Accept: 'application/vnd.github+json',
      },
    });
    if (!respuesta.ok) {
      return Response.json({error: 'Versiones no disponibles.'},
        {status: 502, headers: {'Cache-Control': 'no-store'}});
    }
    const versiones = await respuesta.json();
    if (!Array.isArray(versiones)) throw new Error('Respuesta inesperada.');
    const publicas = versiones.map((version) => ({
      tag_name: version.tag_name,
      published_at: version.published_at,
      body: version.body,
      draft: version.draft,
      assets: (version.assets || []).filter((asset) => asset.name.endsWith('.apk'))
        .map((asset) => ({
          name: asset.name,
          size: asset.size,
          browser_download_url: asset.browser_download_url,
        })),
    }));
    const salida = Response.json(publicas, {
      headers: {'Cache-Control': 'public, max-age=300'},
    });
    if (cache != null) await cache.put(clave, salida.clone());
    return salida;
  } catch {
    return Response.json({error: 'Versiones no disponibles.'},
      {status: 502, headers: {'Cache-Control': 'no-store'}});
  }
};
