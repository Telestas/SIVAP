import assert from 'node:assert/strict';
import {test} from 'node:test';
import {
  crearCentro, renombrarCentro, asignarPrincipal, cambiarRoles,
} from '../administrar.mjs';

class DbFalsa {
  constructor(documentos = {}) {
    this.documentos = documentos;
    this.operador = 'operador-de-prueba';
    this.writes = [];
  }
  async leer(ruta) { return this.documentos[ruta] || null; }
  escritura(ruta, datos, campos) { return {ruta, datos, campos}; }
  async transaccion(operacion) {
    const {writes, resultado} = await operacion('tx');
    this.writes = writes;
    return resultado;
  }
}

const cuenta = {
  uid: 'uid-prueba', email: 'principal@example.org', emailVerified: true,
};

test('el nuevo hospital queda bloqueado para captura clínica', async () => {
  const db = new DbFalsa();
  const resultado = await crearCentro(db, 'Hospital-2', 'Hospital de prueba');
  assert.equal(resultado.captura_habilitada, false);
  assert.deepEqual(db.writes[0].datos, {
    nombre: 'Hospital de prueba', cei_aprobado: false,
    habilitado_pruebas: false,
  });
  assert.equal(db.writes[1].datos.accion, 'crear_centro');
});

test('renombrar centro conserva el código y la aprobación', async () => {
  const db = new DbFalsa({'instituciones/Hospital-1': {
    nombre: 'Nombre anterior', cei_aprobado: true,
  }});
  await renombrarCentro(db, 'Hospital-1', 'Nombre nuevo');
  assert.deepEqual(db.writes[0].campos, ['nombre']);
  assert.deepEqual(db.writes[0].datos, {nombre: 'Nombre nuevo'});
});

test('asignar principal cierra solicitud en el mismo lote y audita', async () => {
  const db = new DbFalsa({
    'instituciones/Hospital-1': {nombre: 'Hospital de prueba'},
    'solicitudes_acceso/uid-prueba': {
      nombre: 'Persona de prueba', correo: cuenta.email,
      institucion_codigo: 'Hospital-1', estado: 'pendiente',
    },
  });
  const resultado = await asignarPrincipal(db, cuenta, 'Hospital-1');
  assert.equal(resultado.rol, 'investigadorPrincipal');
  assert.equal(db.writes.length, 3);
  assert.deepEqual(db.writes[0].datos.roles, ['investigadorPrincipal']);
  assert.equal(db.writes[1].datos.accion, 'asignar_principal');
  assert.equal(db.writes[2].datos.estado, 'aprobado');
});

test('un principal no se asigna a un centro distinto al de su perfil', async () => {
  const db = new DbFalsa({
    'instituciones/Hospital-2': {nombre: 'Hospital de prueba'},
    'investigadores/uid-prueba': {
      nombre: 'Persona de prueba', correo: cuenta.email,
      institucion_codigo: 'Hospital-1', roles: ['reclutador'],
    },
  });
  await assert.rejects(asignarPrincipal(db, cuenta, 'Hospital-2'), /otro centro/);
  assert.deepEqual(db.writes, []);
});

test('cambiar roles registra valor anterior y nuevo', async () => {
  const db = new DbFalsa({'investigadores/uid-prueba': {
    correo: cuenta.email, institucion_codigo: 'Hospital-1', roles: ['reclutador'],
  }});
  await cambiarRoles(db, cuenta, ['reclutador', 'aplicador']);
  assert.deepEqual(db.writes[0].datos.roles, ['reclutador', 'aplicador']);
  assert.deepEqual(db.writes[1].datos.roles_anteriores, ['reclutador']);
  assert.deepEqual(db.writes[1].datos.roles_nuevos, ['reclutador', 'aplicador']);
});

test('roles incompatibles y ascenso a principal requieren procedimiento especial', async () => {
  const db = new DbFalsa();
  await assert.rejects(cambiarRoles(db, cuenta,
    ['aplicador', 'evaluadorDesenlaces']), /cegamiento/);
  await assert.rejects(cambiarRoles(db, cuenta,
    ['investigadorPrincipal']), /asignar-principal/);
  assert.deepEqual(db.writes, []);
});
