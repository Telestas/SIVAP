/** Versiones públicas para la página de descarga y la app móvil. */
export const onRequestGet = async () => {
  try {
    const respuesta = await fetch(
      'https://api.github.com/repos/Telestas/SIVAP/releases?per_page=20',
      {
        headers: {
          Accept: 'application/vnd.github+json',
          'User-Agent': 'SIVAP-Distribucion',
        },
      },
    );
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
    return Response.json(publicas, {
      headers: {'Cache-Control': 'public, max-age=300'},
    });
  } catch {
    return Response.json({error: 'Versiones no disponibles.'},
      {status: 502, headers: {'Cache-Control': 'no-store'}});
  }
};
