"""Sesiones de sincronización."""

import uuid

from conftest import CONTRASENA


def test_salud_responde_con_la_version_del_esquema(cliente):
    r = cliente.get('/api/salud')

    assert r.status_code == 200
    assert r.json()['estado'] == 'ok'
    assert r.json()['esquema'] == '002'


def test_credenciales_correctas_devuelven_token_y_funciones(cliente, investigador):
    investigador(usuario='dra.uno', roles=('reclutador', 'aplicador'))

    r = cliente.post('/api/sesion',
                     json={'usuario': 'dra.uno', 'contrasena': CONTRASENA})

    assert r.status_code == 200
    cuerpo = r.json()
    assert cuerpo['token']
    # PostgreSQL ordena un enum por su orden de declaración, no alfabéticamente,
    # y ese orden es el de las funciones en el ensayo: reclutador, aplicador,
    # evaluador... Sale más útil que el alfabético.
    assert cuerpo['investigador']['roles'] == ['reclutador', 'aplicador']
    assert cuerpo['investigador']['institucion'] == 'HC'


def test_la_contrasena_no_viaja_de_vuelta(cliente, investigador):
    investigador(usuario='dra.uno')

    r = cliente.post('/api/sesion',
                     json={'usuario': 'dra.uno', 'contrasena': CONTRASENA})

    assert CONTRASENA not in r.text
    assert 'credencial' not in r.text


def test_usuario_inexistente_y_contrasena_mala_dan_el_mismo_error(
        cliente, investigador):
    investigador(usuario='dra.uno')

    inexistente = cliente.post(
        '/api/sesion', json={'usuario': 'nadie', 'contrasena': CONTRASENA})
    equivocada = cliente.post(
        '/api/sesion', json={'usuario': 'dra.uno', 'contrasena': 'otra-cosa'})

    # Distinguirlos permitiría averiguar qué usuarios existen probando nombres.
    assert inexistente.status_code == equivocada.status_code == 401
    assert inexistente.json() == equivocada.json()


def test_una_cuenta_dada_de_baja_no_entra(cliente, investigador):
    investigador(usuario='dra.uno', activo=False)

    r = cliente.post('/api/sesion',
                     json={'usuario': 'dra.uno', 'contrasena': CONTRASENA})

    assert r.status_code == 401


def test_dar_de_baja_corta_las_sesiones_ya_abiertas(cliente, sesion, con):
    cabeceras = sesion(usuario='dra.uno')
    assert cliente.get('/api/estudio', headers=cabeceras).status_code == 200

    con.execute("UPDATE investigador SET activo = FALSE WHERE usuario = 'dra.uno'")

    # No se espera a que caduque el token: un mes es demasiado tiempo para
    # alguien que ya no debería tener acceso.
    assert cliente.get('/api/estudio', headers=cabeceras).status_code == 401


def test_sin_token_no_se_entra(cliente):
    assert cliente.get('/api/estudio').status_code == 401


def test_token_inventado_no_sirve(cliente):
    r = cliente.get('/api/estudio',
                    headers={'Authorization': 'Bearer ' + 'x' * 43})

    assert r.status_code == 401


def test_cerrar_sesion_revoca_el_token(cliente, sesion):
    cabeceras = sesion()
    assert cliente.get('/api/estudio', headers=cabeceras).status_code == 200

    assert cliente.delete('/api/sesion', headers=cabeceras).status_code == 204
    assert cliente.get('/api/estudio', headers=cabeceras).status_code == 401


def test_una_sesion_caducada_no_sirve(cliente, sesion, con):
    cabeceras = sesion()
    con.execute("UPDATE sesion SET expira_en = now() - interval '1 day'")

    assert cliente.get('/api/estudio', headers=cabeceras).status_code == 401


def test_el_token_no_se_guarda_en_claro(cliente, sesion, con):
    cabeceras = sesion()
    token = cabeceras['Authorization'].split(' ')[1]

    guardado = con.execute('SELECT token_hash FROM sesion').fetchone()[0]

    # Quien lea la tabla de sesiones no puede suplantar a nadie.
    assert guardado != token
    assert len(guardado) == 64


def test_no_se_abre_sesion_con_un_dispositivo_de_otro(
        cliente, investigador, con):
    otro = investigador(usuario='dra.dos')
    investigador(usuario='dra.uno')
    dispositivo = uuid.uuid4()
    con.execute('INSERT INTO dispositivo (id, investigador_id, etiqueta)'
                ' VALUES (%s, %s, %s)', (dispositivo, otro, 'tableta'))

    r = cliente.post('/api/sesion', json={
        'usuario': 'dra.uno', 'contrasena': CONTRASENA,
        'dispositivo_id': str(dispositivo)})

    assert r.status_code == 403
