# api — servicio central del ensayo LIVERE

FastAPI + PostgreSQL. **La captura de datos no depende de esto**: la app trabaja
sin conexión y el servidor solo consolida (CLAUDE.md §12). Si el servidor se
cae, el equipo sigue capturando.

## Estado

| | |
|---|---|
| Esquema | ✅ verificado contra PostgreSQL 16 |
| Sesiones y funciones | ✅ |
| Registro de dispositivos | ✅ |
| Reparto de la secuencia de aleatorización | ✅ |
| Configuración del estudio y definición de formularios | ✅ |
| **Sincronización** | ❌ siguiente |
| **Exportación `.xlsx`** | ❌ |

## Correr

```bash
docker run --rm -d --name sivap-db -p 5544:5432 -e POSTGRES_PASSWORD=x postgres:16
export DATABASE_URL=postgresql://postgres:x@localhost:5544/postgres

pip install -e '.[pruebas]'
python -m pytest pruebas -q                     # 30 pruebas, contra Postgres real
uvicorn sivap.principal:app --reload
```

Las pruebas aplican las migraciones ellas mismas y vacían las tablas entre
casos. No hacen falta ni `psql` ni datos previos.

## La primera cuenta

No hay registro abierto: en un ensayo donde los permisos sostienen el cegamiento,
eso no es una carencia.

```bash
python -m sivap.cli crear-investigador \
  --usuario dra.uno --nombre "Dra. Uno" --institucion HC \
  --rol reclutador --rol aplicador
```

Avisa —no impide— si la persona acumula **aplicador y evaluador de desenlaces**:
esa combinación rompe el cegamiento del desenlace principal, porque quien aplicó
el protocolo sabe qué rama es y luego juzgaría si la extubación falló. Admitirlo
es decisión de la investigadora principal; pasar desapercibido, no.

## Rutas

| Ruta | Quién | Qué hace |
|---|---|---|
| `GET /api/salud` | cualquiera | Vida del servicio y versión del esquema |
| `POST /api/sesion` | cualquiera | Abre sesión de sincronización |
| `DELETE /api/sesion` | autenticado | Revoca la sesión en curso |
| `GET /api/estudio` | autenticado | Centros, definición de formularios, secuencia activa |
| `POST /api/dispositivos` | autenticado | Registra el dispositivo |
| `POST /api/dispositivos/{id}/tramo` | reclutador, investigador principal | Entrega su tramo de la secuencia |

**Restricción CLAUDE.md §11**: ninguna ruta sin declarar qué función puede
invocarla. Se declara con la dependencia `exigir_rol`, y hay una prueba por
cada restricción.

## Tres decisiones que conviene entender

### El reparto por tramos es lo que hace posible enrolar sin conexión

Si todos los dispositivos consumieran de la misma lista, dos sin cobertura
asignarían ambos la posición siguiente y, al sincronizar, dos pacientes
reclamarían la misma. **En silencio.**

Cada dispositivo recibe un tramo propio y disjunto; la base rechaza cualquier
solapamiento y la clave primaria de `asignacion` convierte una colisión en un
error visible. Es el equivalente digital de los sobres sellados y numerados.

Un dispositivo solo recibe **los bits de su tramo**, nunca la secuencia
completa: si se pierde el teléfono se compromete su tramo, no el ensayo entero.
Y solo se le entrega uno nuevo cuando el anterior se agotó, para no repartir la
secuencia entre dispositivos que no la están usando.

### La sesión dura un mes, y no es descuido

Un teléfono puede pasar semanas sin cobertura. Caducarle la sesión significaría
que no puede enviar lo que ya capturó. Se compensa con revocación: un teléfono
perdido se corta desde `sesion` sin tocar la credencial de nadie, y dar de baja
a un investigador le corta el acceso en el acto, sin esperar a que caduque.

### Sin ORM

El SQL va escrito a mano, igual que el esquema. Un sistema que guarda datos
clínicos debe poder leerse sin descifrar antes la capa de abstracción de nadie
(CLAUDE.md, convenciones técnicas).

## Lo que falta decidir

1. **Identificadores.** El esquema usa `uuid`; la app genera cadenas con prefijo
   (`p-3f9a…`). Hay que pasar `Ids.nuevo` a UUIDv4 antes de la primera
   sincronización.
2. **Cuándo pide tramo la app.** Falta el umbral —¿al quedarle 5 posiciones?— y,
   sobre todo, qué hace si se queda sin tramo y sin conexión. Debe **dejar de
   enrolar**: improvisar una asignación es exactamente lo que la aleatorización
   pre-generada evita.
3. **Conflictos en la sincronización.** «Último gana» está decidido; falta si el
   servidor genera auditoría al descartar una versión, y quién la firma.
