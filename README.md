# SIVAP — Sistema de Validación de Protocolos

Sistema para automatizar un estudio de cohorte que valida un protocolo clínico nuevo
frente al vigente, en un hospital cubano. Captura de datos **offline-first** en visitas
fijas (Día 1, 3, 5, 10, 14), sincronización posterior y exportación a Excel para análisis.

> Nombre de trabajo provisional. Estado: **Hito 1 — interfaz y capa de datos local**.

## Documentación

| Documento | Contenido |
|---|---|
| [CLAUDE.md](CLAUDE.md) | Constitución del repositorio: restricciones no negociables, glosario y convenciones |
| [BASES_MVP_SIVAP.md](BASES_MVP_SIVAP.md) | Alcance del MVP, arquitectura, roles y decisiones pendientes |
| [docs/HITO_1.md](docs/HITO_1.md) | Qué se entrega en este hito y qué revisar |
| [docs/PENDIENTE.md](docs/PENDIENTE.md) | Qué falta para completar el MVP |
| [docs/DISTRIBUCION.md](docs/DISTRIBUCION.md) | Cómo llega el APK a los investigadores, y qué decidir antes |
| [app/README.md](app/README.md) | Cómo correr la app y dónde vive cada restricción |
| [design/](design/) | El canvas de Claude Design del que sale la interfaz |

## Estructura

```
app/           cliente Flutter (móvil + web)
deploy/        despliegue con Docker: Postgres, panel web, TLS
design/        canvas de diseño, como referencia
docs/          notas por hito y decisiones
web-descarga/  página de descarga del APK
```

## Verificación

Cada push analiza y prueba la app en GitHub Actions — el equipo no tiene ancho
de banda para descargar el SDK de Flutter:

```bash
gh workflow run verificar.yml && gh run watch
```

## Arquitectura

- **App móvil + web**: Flutter (Dart), persistencia local cifrada (Drift o Isar).
- **Backend**: FastAPI (Python) + PostgreSQL.
- **Sync**: cola local con timestamp, resolución "último gana" + auditoría.
- **Exportación**: .xlsx vía openpyxl, ficha de identidad y datos clínicos por separado.

## Reglas que todo cambio debe respetar

1. Ficha del paciente y registro de visita son entidades **separadas**.
2. **Sin ediciones silenciosas**: toda corrección genera entrada de auditoría.
3. Formularios de visita **configurables como datos**, no hardcodeados.
4. Módulo de **asignación de protocolo desacoplado** (aleatorización pre-generada).
5. **Cifrado obligatorio** en reposo y en tránsito.
6. Cada endpoint declara **qué rol** puede invocarlo.
7. **Offline-first real**: capturar datos nunca requiere conexión.
8. Sin enrolamiento de pacientes reales hasta el flag de **aprobación del CEI**.

Detalle completo en [CLAUDE.md](CLAUDE.md).

## Privacidad

Repositorio **privado**. No versionar datos de pacientes, exportaciones ni credenciales
(ver [.gitignore](.gitignore)).
