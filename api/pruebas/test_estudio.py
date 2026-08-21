"""Configuración que descarga el dispositivo."""


def test_devuelve_los_centros_con_su_estado_de_cei(cliente, sesion, centro):
    cabeceras = sesion()
    centro(codigo='IC', nombre='Segundo centro', coordinador=False,
           cei_aprobado=True)

    cuerpo = cliente.get('/api/estudio', headers=cabeceras).json()

    por_codigo = {i['codigo']: i for i in cuerpo['instituciones']}
    assert por_codigo['HC']['coordinador'] is True
    assert por_codigo['HC']['cei_aprobado'] is False
    assert por_codigo['IC']['cei_aprobado'] is True


def test_sin_aprobacion_del_cei_no_admite_pacientes_reales(cliente, sesion):
    cabeceras = sesion()

    cuerpo = cliente.get('/api/estudio', headers=cabeceras).json()

    # Restricción CLAUDE.md §13.
    assert cuerpo['admite_pacientes_reales'] is False


def test_basta_un_centro_aprobado_para_admitir_pacientes(
        cliente, sesion, centro):
    cabeceras = sesion()
    centro(codigo='IC', coordinador=False, cei_aprobado=True)

    cuerpo = cliente.get('/api/estudio', headers=cabeceras).json()

    # La aprobación es por centro: uno puede empezar antes que otro.
    assert cuerpo['admite_pacientes_reales'] is True


def test_sirve_la_definicion_de_formularios(cliente, sesion, con):
    cabeceras = sesion()
    con.execute(
        "INSERT INTO definicion_formulario (version, definicion, activa)"
        " VALUES ('anexo4-v1', '{\"eventos\": []}', TRUE)")

    cuerpo = cliente.get('/api/estudio', headers=cabeceras).json()

    # Restricción CLAUDE.md §5: ajustar el protocolo es publicar una versión
    # nueva de esto, no recompilar la app.
    assert cuerpo['definicion_formulario_version'] == 'anexo4-v1'
    assert cuerpo['definicion_formulario'] == {'eventos': []}


def test_la_configuracion_NO_lleva_la_secuencia_completa(
        cliente, sesion, secuencia):
    cabeceras = sesion()
    codigo = '1100101011' * 5
    secuencia(codigo=codigo)

    respuesta = cliente.get('/api/estudio', headers=cabeceras)

    # La secuencia se entrega por tramos, nunca entera: quien tuviera el código
    # completo sabría qué rama le toca a cada paciente futuro del estudio.
    assert codigo not in respuesta.text
    cuerpo = respuesta.json()
    assert cuerpo['secuencia_etiqueta'] == 'prueba'
    assert cuerpo['secuencia_longitud'] == 50
    assert 'codigo_binario' not in cuerpo
