"""Recepción de lo que capturó un dispositivo.

Lo que se comprueba aquí no es que la ruta responda: es que las tres reglas que
sostienen el estudio siguen en pie cuando los datos llegan de un teléfono que
estuvo semanas sin cobertura. Que reenviar no duplica, que dos pacientes no
pueden ocupar la misma posición de la secuencia, y que una corrección no borra
lo anterior.
"""

import uuid

import pytest


@pytest.fixture
def centro_aprobado(con, centro):
    """Un centro con la aprobación del CEI: sin ella no entran pacientes."""

    def crear(codigo='HC'):
        existe = con.execute('SELECT 1 FROM institucion WHERE codigo = %s',
                             (codigo,)).fetchone()
        if not existe:
            centro(codigo=codigo, coordinador=(codigo == 'HC'),
                   cei_aprobado=True)
        else:
            con.execute(
                "UPDATE institucion SET cei_aprobado = TRUE,"
                " cei_codigo = 'CEI-1', cei_aprobado_en = '2026-01-01'"
                ' WHERE codigo = %s', (codigo,))
        return codigo
    return crear


@pytest.fixture
def dispositivo(cliente):
    def registrar(cabeceras, ident=None):
        ident = ident or uuid.uuid4()
        r = cliente.post('/api/dispositivos', headers=cabeceras,
                         json={'id': str(ident), 'etiqueta': 'teléfono de sala'})
        assert r.status_code == 201, r.text
        return str(ident)
    return registrar


@pytest.fixture
def campo():
    """Un lote de campo completo: paciente, evento con valores y auditoría."""

    def construir(dispositivo_id, posicion=1, protocolo='a', codigo=None,
                  **extra):
        paciente_id = str(uuid.uuid4())
        evento_id = str(uuid.uuid4())
        lote = {
            'id': str(uuid.uuid4()),
            'dispositivo_id': dispositivo_id,
            'pacientes': [{
                'id': paciente_id,
                'codigo': codigo or f'HC-{posicion:03d}',
                'institucion_codigo': 'HC',
                'edad': 62,
                'sexo': 'masculino',
                'enrolado_en': '2026-09-01T10:00:00Z',
                'identidad': {
                    'nombre': 'Nombre Inventado',
                    'numero_historia_clinica': '123456',
                    'telefono_principal': '55512345',
                },
                'asignacion': {
                    'secuencia_etiqueta': 'prueba',
                    'posicion': posicion,
                    'protocolo': protocolo,
                    'asignado_en': '2026-09-01T10:00:00Z',
                },
            }],
            'eventos': [{
                'id': evento_id,
                'paciente_id': paciente_id,
                'tipo': 'prueba_ventilacion_espontanea',
                'ocurrencia': 1,
                'fecha_ocurrencia': '2026-09-02',
                'institucion_codigo': 'HC',
                'fecha_captura': '2026-09-02T14:30:00Z',
                'valores': [
                    {'campo': 'rsbi_categoria', 'tipo': 'lista',
                     'valor': 'menor_igual_105'},
                    {'campo': 'duracion_minutos', 'tipo': 'numero',
                     'valor': '30'},
                ],
            }],
            'auditoria': [],
        }
        lote.update(extra)
        return lote
    return construir


@pytest.fixture
def enviar(cliente):
    def hacer(lote, cabeceras, espera=200):
        r = cliente.post('/api/sincronizacion', headers=cabeceras, json=lote)
        assert r.status_code == espera, r.text
        cuerpo = r.json()
        if espera == 200:
            # Todo registro del lote acaba contado de un lado o del otro. Si
            # esto falla, el diario del lote está mintiendo sobre algo.
            assert cuerpo['registros'] == (cuerpo['aceptados']
                                           + cuerpo['rechazados']), cuerpo
        return cuerpo
    return hacer


def _rechazo(resultado, tipo):
    """El rechazo de ese tipo, y falla si no hay exactamente uno."""
    de_ese_tipo = [r for r in resultado['detalle'] if r['tipo'] == tipo]
    assert len(de_ese_tipo) == 1, resultado['detalle']
    return de_ese_tipo[0]


@pytest.fixture
def listo(sesion, secuencia, centro_aprobado, dispositivo):
    """Sesión abierta, secuencia activa, centro aprobado y aparato registrado."""

    def preparar(usuario='prueba', roles=('reclutador',)):
        centro_aprobado()
        cabeceras = sesion(usuario=usuario, roles=roles)
        secuencia()
        return cabeceras, dispositivo(cabeceras)
    return preparar


# ── Lo que tiene que entrar ───────────────────────────────────────


def test_un_lote_de_campo_entra_entero(listo, campo, enviar, con):
    cabeceras, aparato = listo()

    resultado = enviar(campo(aparato), cabeceras)

    # Paciente, evento y sus dos valores.
    assert (resultado['aceptados'], resultado['rechazados']) == (4, 0)
    assert resultado['ya_recibido'] is False

    assert con.execute('SELECT count(*) FROM paciente').fetchone()[0] == 1
    assert con.execute('SELECT count(*) FROM identidad').fetchone()[0] == 1
    assert con.execute('SELECT count(*) FROM asignacion').fetchone()[0] == 1
    assert con.execute('SELECT count(*) FROM evento_valor').fetchone()[0] == 2


def test_el_dataset_sale_con_la_rama_en_a_b_y_sin_identidad(
        listo, campo, enviar, con):
    """Lo que recibe el bioestadista. Nunca desciegado (CLAUDE.md §2)."""
    cabeceras, aparato = listo()
    enviar(campo(aparato), cabeceras)

    filas = con.execute(
        'SELECT paciente, rama, campo, valor FROM dataset_clinico'
        ' ORDER BY campo').fetchall()

    assert [f[1] for f in filas] == ['a', 'a']
    assert 'Nombre Inventado' not in str(filas)


def test_se_anota_cuando_sincronizo_el_dispositivo(listo, campo, enviar, con):
    cabeceras, aparato = listo()
    enviar(campo(aparato), cabeceras)

    ultima = con.execute(
        'SELECT ultima_sincronizacion FROM dispositivo WHERE id = %s',
        (aparato,)).fetchone()[0]
    assert ultima is not None


# ── Reenviar no duplica ───────────────────────────────────────────


def test_reenviar_el_mismo_lote_devuelve_el_resultado_guardado(
        listo, campo, enviar, con):
    """El caso que va a pasar de verdad: se guardó y la respuesta no llegó."""
    cabeceras, aparato = listo()
    lote = campo(aparato)

    primero = enviar(lote, cabeceras)
    segundo = enviar(lote, cabeceras)

    assert segundo['ya_recibido'] is True
    assert segundo['aceptados'] == primero['aceptados']
    assert con.execute('SELECT count(*) FROM paciente').fetchone()[0] == 1
    assert con.execute('SELECT count(*) FROM evento_valor').fetchone()[0] == 2


def test_el_mismo_paciente_en_otro_lote_tampoco_duplica(
        listo, campo, enviar, con):
    """El dispositivo puede reagrupar lo pendiente en lotes distintos."""
    cabeceras, aparato = listo()
    lote = campo(aparato)

    enviar(lote, cabeceras)
    otro = dict(lote, id=str(uuid.uuid4()))
    resultado = enviar(otro, cabeceras)

    assert resultado['ya_recibido'] is False
    assert resultado['rechazados'] == 0
    assert con.execute('SELECT count(*) FROM paciente').fetchone()[0] == 1
    # Y no aparecen versiones nuevas de unos valores que no cambiaron.
    assert con.execute('SELECT count(*) FROM evento_valor').fetchone()[0] == 2


# ── Aleatorización ────────────────────────────────────────────────


def test_dos_pacientes_no_pueden_ocupar_la_misma_posicion(
        listo, campo, enviar, con):
    """La colisión pasa de silenciosa a error, que es la diferencia que importa.

    Dos dispositivos mal configurados con el mismo tramo asignarían ambos la
    posición 1. Aquí el segundo se rechaza con su motivo y el resto del lote
    entra igual.
    """
    cabeceras, aparato = listo()
    enviar(campo(aparato, posicion=1), cabeceras)

    # Códigos distintos a propósito: lo que tiene que chocar es la posición de
    # la secuencia, no el nombre que le puso el dispositivo al paciente.
    resultado = enviar(campo(aparato, posicion=1, codigo='HC-777'), cabeceras)

    rechazo = _rechazo(resultado, 'paciente')
    assert 'asignacion_pkey' in rechazo['motivo']
    assert con.execute('SELECT count(*) FROM asignacion').fetchone()[0] == 1
    # La ficha tampoco entró: los tres van juntos o no va ninguno.
    assert con.execute('SELECT count(*) FROM paciente').fetchone()[0] == 1


def test_la_rama_que_no_coincide_con_la_secuencia_se_rechaza(
        listo, campo, enviar, con):
    """La comprobación que haría un auditor externo, hecha por la base.

    La secuencia de prueba dicta «a» en la posición 1. Un dispositivo que
    reclame «b» ahí, sea por error o por lo otro, no llega a guardarse.
    """
    cabeceras, aparato = listo()

    resultado = enviar(campo(aparato, posicion=1, protocolo='b'), cabeceras)

    assert 'no coincide con la secuencia' in _rechazo(resultado, 'paciente')['motivo']
    assert con.execute('SELECT count(*) FROM paciente').fetchone()[0] == 0


def test_una_posicion_fuera_de_la_secuencia_no_entra(listo, campo, enviar):
    cabeceras, aparato = listo()

    resultado = enviar(campo(aparato, posicion=5000), cabeceras)

    assert 'fuera de la secuencia' in _rechazo(resultado, 'paciente')['motivo']


# ── Correcciones ──────────────────────────────────────────────────


def test_una_correccion_anade_version_y_conserva_la_anterior(
        listo, campo, enviar, con):
    """CLAUDE.md §3. Poder demostrar qué decía un campo en una fecha concreta
    no es una comodidad: es lo que se pregunta en una inspección."""
    cabeceras, aparato = listo()
    lote = campo(aparato)
    enviar(lote, cabeceras)

    corregido = dict(lote, id=str(uuid.uuid4()))
    corregido['eventos'][0]['valores'][1]['valor'] = '45'
    enviar(corregido, cabeceras)

    versiones = con.execute(
        'SELECT version, valor FROM evento_valor WHERE campo = %s'
        ' ORDER BY version', ('duracion_minutos',)).fetchall()
    assert versiones == [(1, '30'), (2, '45')]

    vigente = con.execute(
        'SELECT valor FROM evento_valor_vigente WHERE campo = %s',
        ('duracion_minutos',)).fetchone()[0]
    assert vigente == '45'


def test_la_correccion_llega_con_su_entrada_de_auditoria(
        listo, campo, enviar, con):
    cabeceras, aparato = listo()
    lote = campo(aparato)
    enviar(lote, cabeceras)

    evento_id = lote['eventos'][0]['id']
    correccion = dict(lote, id=str(uuid.uuid4()), auditoria=[{
        'id': str(uuid.uuid4()),
        'ocurrido_en': '2026-09-03T09:00:00Z',
        'entidad': 'evento',
        'entidad_id': evento_id,
        'descripcion_objetivo': 'HC-001 · PVE · 1',
        'campo': 'duracion_minutos',
        'valor_anterior': '30',
        'valor_nuevo': '45',
        'motivo': 'Error de transcripción del registro de enfermería.',
    }])
    correccion['eventos'][0]['valores'][1]['valor'] = '45'
    enviar(correccion, cabeceras)

    fila = con.execute(
        'SELECT valor_anterior, valor_nuevo, motivo, dispositivo_id'
        ' FROM auditoria').fetchone()
    assert fila[0] == '30' and fila[1] == '45'
    assert str(fila[3]) == aparato


def test_una_auditoria_sin_motivo_no_entra(listo, campo, enviar):
    """El motivo lo exige la capa de datos, no la pantalla.

    Y se rechaza esa entrada sola: el resto del lote entra. Cortar el envío
    entero por una corrección mal formada dejaría al dispositivo sin poder
    sincronizar lo que sí está bien.
    """
    cabeceras, aparato = listo()
    lote = campo(aparato, auditoria=[{
        'id': str(uuid.uuid4()),
        'ocurrido_en': '2026-09-03T09:00:00Z',
        'entidad': 'evento',
        'entidad_id': str(uuid.uuid4()),
        'descripcion_objetivo': 'algo',
        'campo': 'x',
        'valor_anterior': None,
        'valor_nuevo': '1',
        'motivo': '   ',
    }])

    resultado = enviar(lote, cabeceras)

    assert resultado['aceptados'] == 4
    assert 'motivo' in _rechazo(resultado, 'auditoria')['motivo']


# ── Rechazo por registro, no por lote ─────────────────────────────


def test_un_registro_malo_no_tumba_lo_que_estaba_bien(
        listo, campo, enviar, con):
    """Todo o nada dejaría a un teléfono sin poder sincronizar nunca."""
    cabeceras, aparato = listo()
    lote = campo(aparato)
    lote['eventos'].append({
        'id': str(uuid.uuid4()),
        # Un paciente que no existe ni llega en este lote.
        'paciente_id': str(uuid.uuid4()),
        'tipo': 'extubacion',
        'ocurrencia': 1,
        'fecha_ocurrencia': '2026-09-03',
        'institucion_codigo': 'HC',
        'fecha_captura': '2026-09-03T08:00:00Z',
        'valores': [{'campo': 'test_fuga', 'tipo': 'booleano', 'valor': 'true'}],
    })

    resultado = enviar(lote, cabeceras)

    # El evento huérfano y su único valor. Lo demás entra.
    assert (resultado['aceptados'], resultado['rechazados']) == (4, 2)
    assert con.execute('SELECT count(*) FROM paciente').fetchone()[0] == 1
    assert con.execute('SELECT count(*) FROM evento').fetchone()[0] == 1


def test_el_motivo_del_rechazo_queda_escrito_en_el_diario(
        listo, campo, enviar, con):
    """«Esto llegó o no llegó» tiene que poder responderse meses después."""
    cabeceras, aparato = listo()
    enviar(campo(aparato, posicion=1), cabeceras)
    lote = campo(aparato, posicion=1, codigo='HC-777')

    enviar(lote, cabeceras)

    registros, aceptados, rechazados, detalle = con.execute(
        'SELECT registros, aceptados, rechazados, detalle'
        ' FROM lote_sincronizacion WHERE id = %s', (lote['id'],)).fetchone()
    # El paciente choca en la posición, el evento se queda sin paciente al que
    # colgarse y sus dos valores se van con él.
    assert (aceptados, rechazados) == (0, 4)
    assert registros == aceptados + rechazados
    assert [r['motivo'] for r in detalle if r['tipo'] == 'paciente']


# ── Comité de Ética ───────────────────────────────────────────────


def test_sin_aprobacion_del_cei_el_paciente_no_entra(
        cliente, sesion, secuencia, dispositivo, campo, enviar, con):
    """Restricción CLAUDE.md §13, comprobada también aquí.

    La app ya lo sabe, pero un dispositivo con configuración vieja no debe poder
    meter pacientes reales en un centro que todavía no puede reclutarlos.
    """
    cabeceras = sesion()          # centro HC creado sin aprobación
    secuencia()
    aparato = dispositivo(cabeceras)

    resultado = enviar(campo(aparato), cabeceras)

    assert 'Comité de Ética' in _rechazo(resultado, 'paciente')['motivo']
    assert con.execute('SELECT count(*) FROM paciente').fetchone()[0] == 0


def test_el_paciente_rechazado_entra_en_cuanto_el_centro_queda_aprobado(
        cliente, sesion, secuencia, dispositivo, campo, enviar, con,
        centro_aprobado):
    """Por eso se rechaza el registro y no el lote: la cola no se pierde."""
    cabeceras = sesion()
    secuencia()
    aparato = dispositivo(cabeceras)
    lote = campo(aparato)
    enviar(lote, cabeceras)

    centro_aprobado()
    resultado = enviar(dict(lote, id=str(uuid.uuid4())), cabeceras)

    assert resultado['rechazados'] == 0
    assert con.execute('SELECT count(*) FROM paciente').fetchone()[0] == 1


# ── Quién puede sincronizar y con qué aparato ─────────────────────


def test_la_autoria_sale_de_la_sesion_y_no_del_lote(listo, campo, enviar, con):
    """Un dispositivo pertenece a una persona, así que lo que sube es suyo.

    Aceptar el autor que venga en el envío permitiría atribuir capturas a
    cualquiera, y entonces el registro de auditoría dejaría de significar nada.
    """
    cabeceras, aparato = listo()
    enviar(campo(aparato), cabeceras)

    quien = con.execute(
        "SELECT id FROM investigador WHERE usuario = 'prueba'").fetchone()[0]
    assert con.execute(
        'SELECT recolector_id FROM evento').fetchone()[0] == quien
    assert con.execute(
        'SELECT autor_id FROM evento_valor LIMIT 1').fetchone()[0] == quien


def test_el_analista_no_sincroniza(listo, campo, enviar):
    """Su función es leer el dataset, no escribir en el estudio."""
    cabeceras, aparato = listo(usuario='analista', roles=('analista',))

    enviar(campo(aparato), cabeceras, espera=403)


def test_nadie_sincroniza_con_el_dispositivo_de_otro(
        listo, campo, enviar, sesion, centro_aprobado):
    cabeceras, aparato = listo(usuario='dra.uno')
    otras = sesion(usuario='dra.dos')

    enviar(campo(aparato), otras, espera=403)


def test_el_dispositivo_sin_registrar_no_sincroniza(listo, campo, enviar):
    cabeceras, _ = listo()

    enviar(campo(str(uuid.uuid4())), cabeceras, espera=404)


def test_sin_sesion_no_se_sincroniza(cliente, campo):
    r = cliente.post('/api/sincronizacion', json=campo(str(uuid.uuid4())))
    assert r.status_code == 401
