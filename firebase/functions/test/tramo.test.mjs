import {test} from 'node:test';
import assert from 'node:assert/strict';
import {siguienteTramo} from '../tramo.mjs';

test('dos peticiones consecutivas no comparten ninguna posición', () => {
  const secuencia = {
    etiqueta: 'prueba', codigo_binario: '101100',
    siguiente: 1, tamano_tramo: 4,
  };
  const primero = siguienteTramo(secuencia);
  const segundo = siguienteTramo({...secuencia, siguiente: primero.hasta});
  assert.deepEqual([primero.desde, primero.hasta, primero.codigo_binario],
      [1, 5, '1011']);
  assert.deepEqual([segundo.desde, segundo.hasta, segundo.codigo_binario],
      [5, 7, '00']);
  assert.equal(siguienteTramo({...secuencia, siguiente: segundo.hasta}), null);
});
