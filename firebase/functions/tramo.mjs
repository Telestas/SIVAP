/** Toma únicamente el siguiente rango de una secuencia ya generada. */
export function siguienteTramo(secuencia) {
  const desde = secuencia.siguiente;
  const hasta = Math.min(desde + secuencia.tamano_tramo,
      secuencia.codigo_binario.length + 1);
  if (desde < 1 || desde >= hasta) return null;
  return {
    desde, hasta, consumidas: 0,
    etiqueta: secuencia.etiqueta,
    codigo_binario: secuencia.codigo_binario.slice(desde - 1, hasta - 1),
  };
}
