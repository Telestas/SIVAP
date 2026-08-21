"""Registro de dispositivos y reparto de la secuencia de aleatorización."""

import uuid

import pytest


@pytest.fixture
def registrar(cliente):
    def hacer(cabeceras, etiqueta='tableta de sala', ident=None):
        ident = ident or uuid.uuid4()
        r = cliente.post('/api/dispositivos', headers=cabeceras,
                         json={'id': str(ident), 'etiqueta': etiqueta})
        assert r.status_code == 201, r.text
        return ident
    return hacer


def test_se_registra_con_el_identificador_que_trae_el_dispositivo(
        cliente, sesion, registrar):
    cabeceras = sesion()
    ident = uuid.uuid4()

    registrar(cabeceras, ident=ident)

    # Lo genera el dispositivo porque tiene que poder crearse sin conexión.
    r = cliente.post('/api/dispositivos', headers=cabeceras,
                     json={'id': str(ident), 'etiqueta': 'otro nombre'})
    assert r.status_code == 201
    assert r.json()['etiqueta'] == 'otro nombre'


def test_nadie_se_apropia_del_dispositivo_de_otro(
        cliente, sesion, registrar, investigador):
    ident = registrar(sesion(usuario='dra.uno'))
    otras = sesion(usuario='dra.dos')

    r = cliente.post('/api/dispositivos', headers=otras,
                     json={'id': str(ident), 'etiqueta': 'mío ahora'})

    # Si dos personas comparten teléfono se registra dos veces, con
    # identificadores distintos: si no, no habría forma de saber quién capturó
    # qué.
    assert r.status_code == 409


def test_el_primer_tramo_empieza_en_la_posicion_uno(
        cliente, sesion, registrar, secuencia):
    cabeceras = sesion()
    secuencia()
    ident = registrar(cabeceras)

    cuerpo = cliente.post(f'/api/dispositivos/{ident}/tramo',
                          headers=cabeceras).json()

    assert (cuerpo['desde'], cuerpo['hasta']) == (1, 26)
    assert cuerpo['consumidas'] == 0
    assert len(cuerpo['codigo_binario']) == 25


def test_el_dispositivo_solo_recibe_los_bits_de_su_tramo(
        cliente, sesion, registrar, secuencia):
    cabeceras = sesion()
    codigo = '0101010101' * 10
    secuencia(codigo=codigo)
    ident = registrar(cabeceras)

    cuerpo = cliente.post(f'/api/dispositivos/{ident}/tramo',
                          headers=cabeceras).json()

    # Si se pierde el teléfono, se compromete su tramo, no el ensayo entero.
    assert cuerpo['codigo_binario'] == codigo[0:25]
    assert codigo not in str(cuerpo)


def test_pedir_tramo_dos_veces_no_reparte_secuencia_de_mas(
        cliente, sesion, registrar, secuencia):
    cabeceras = sesion()
    secuencia()
    ident = registrar(cabeceras)

    primero = cliente.post(f'/api/dispositivos/{ident}/tramo',
                           headers=cabeceras).json()
    segundo = cliente.post(f'/api/dispositivos/{ident}/tramo',
                           headers=cabeceras).json()

    # Mientras le queden posiciones, se le devuelve el mismo: repartir la
    # secuencia entre dispositivos que no la usan la agota sin pacientes.
    assert (primero['desde'], primero['hasta']) == \
           (segundo['desde'], segundo['hasta'])


def test_agotado_el_tramo_se_entrega_el_siguiente(
        cliente, sesion, registrar, secuencia, consumir_posiciones):
    cabeceras = sesion()
    secuencia()
    ident = registrar(cabeceras)
    cliente.post(f'/api/dispositivos/{ident}/tramo', headers=cabeceras)

    consumir_posiciones(ident, 'prueba', 1, 26)

    cuerpo = cliente.post(f'/api/dispositivos/{ident}/tramo',
                          headers=cabeceras).json()
    assert (cuerpo['desde'], cuerpo['hasta']) == (26, 51)


def test_dos_dispositivos_reciben_tramos_disjuntos(
        cliente, sesion, registrar, secuencia):
    """Este es el problema que el reparto por tramos existe para resolver."""
    secuencia()
    una = sesion(usuario='dra.uno')
    otra = sesion(usuario='dra.dos')
    ident_a = registrar(una)
    ident_b = registrar(otra)

    a = cliente.post(f'/api/dispositivos/{ident_a}/tramo', headers=una).json()
    b = cliente.post(f'/api/dispositivos/{ident_b}/tramo', headers=otra).json()

    # Sin esto, dos teléfonos sin cobertura asignarían la misma posición y, al
    # sincronizar, dos pacientes reclamarían la misma rama. En silencio.
    assert a['hasta'] <= b['desde'] or b['hasta'] <= a['desde']
    assert (a['desde'], a['hasta']) == (1, 26)
    assert (b['desde'], b['hasta']) == (26, 51)


def test_el_ultimo_tramo_no_se_pasa_del_final_de_la_secuencia(
        cliente, sesion, registrar, secuencia):
    cabeceras = sesion()
    secuencia(codigo='0101010101')          # 10 posiciones, tramo de 25
    ident = registrar(cabeceras)

    cuerpo = cliente.post(f'/api/dispositivos/{ident}/tramo',
                          headers=cabeceras).json()

    assert (cuerpo['desde'], cuerpo['hasta']) == (1, 11)
    assert len(cuerpo['codigo_binario']) == 10


def test_secuencia_agotada_es_un_error_no_una_improvisacion(
        cliente, sesion, registrar, secuencia, consumir_posiciones):
    cabeceras = sesion()
    secuencia(codigo='01')
    ident = registrar(cabeceras)
    cliente.post(f'/api/dispositivos/{ident}/tramo', headers=cabeceras)
    consumir_posiciones(ident, 'prueba', 1, 3)

    r = cliente.post(f'/api/dispositivos/{ident}/tramo', headers=cabeceras)

    # Enrolar más allá de la secuencia prevista es un error del estudio.
    assert r.status_code == 409
    assert 'agotada' in r.json()['detail']


def test_sin_secuencia_activa_no_hay_tramos(cliente, sesion, registrar):
    cabeceras = sesion()
    ident = registrar(cabeceras)

    r = cliente.post(f'/api/dispositivos/{ident}/tramo', headers=cabeceras)

    assert r.status_code == 409


def test_quien_no_enrola_no_pide_tramos(
        cliente, sesion, registrar, secuencia):
    """La ruta declara su función, como exige CLAUDE.md §11."""
    secuencia()
    aplicador = sesion(usuario='dr.aplica', roles=('aplicador',))
    ident = registrar(aplicador)

    r = cliente.post(f'/api/dispositivos/{ident}/tramo', headers=aplicador)

    # El aplicador ejecuta el protocolo; no asigna ramas.
    assert r.status_code == 403


def test_no_se_pide_tramo_para_el_dispositivo_de_otro(
        cliente, sesion, registrar, secuencia):
    secuencia()
    ident = registrar(sesion(usuario='dra.uno'))
    otras = sesion(usuario='dra.dos')

    r = cliente.post(f'/api/dispositivos/{ident}/tramo', headers=otras)

    assert r.status_code == 403


def test_los_tramos_quedan_registrados_para_auditoria(
        cliente, sesion, registrar, secuencia, con):
    cabeceras = sesion()
    secuencia()
    ident = registrar(cabeceras)
    cliente.post(f'/api/dispositivos/{ident}/tramo', headers=cabeceras)

    fila = con.execute(
        'SELECT dispositivo_id, institucion_codigo, lower(tramo), upper(tramo)'
        ' FROM secuencia_rango').fetchone()

    # Quién recibió qué parte de la secuencia y cuándo tiene que poder
    # reconstruirse: es parte de auditar la aleatorización.
    assert fila[0] == ident
    assert fila[1] == 'HC'
    assert (fila[2], fila[3]) == (1, 26)
