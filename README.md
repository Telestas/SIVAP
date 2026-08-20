# SIVAP — Sistema de captura del ensayo LIVERE

Sistema para conducir y registrar el **ensayo clínico LIVERE**: validación de un
protocolo de liberación de la ventilación mecánica invasiva en cuidados intensivos,
en entornos de recursos limitados. Ensayo controlado, aleatorizado, multicéntrico,
prospectivo y longitudinal, en tres centros de La Habana.

Captura **offline-first** por eventos clínicos —no por calendario—, base local
cifrada, sincronización posterior y exportación a Excel para análisis.

> **SIVAP** es el nombre provisional del sistema; **LIVERE** es el nombre del estudio.
> Estado: **reencaminamiento tras revisar las fuentes reales** (20 ago 2026).

## Repositorio público

Este repositorio es **público**. Nada identificable entra aquí: sin nombres de
investigadores, sin nombres de centros, sin datos de pacientes, sin semillas reales
ni credenciales. Los datos de demostración son inventados y están marcados como
tales. Esa información vive en el expediente del estudio.

## Documentación

| Documento | Contenido |
|---|---|
| [CLAUDE.md](CLAUDE.md) | Constitución del repositorio: restricciones no negociables, glosario clínico y convenciones |
| [BASES_MVP_SIVAP.md](BASES_MVP_SIVAP.md) | Diseño del ensayo, roles, modelo de eventos y campos del Anexo 4 |
| [docs/REENCAMINAMIENTO.md](docs/REENCAMINAMIENTO.md) | Plan de corrección de rumbo y su estado |
| [docs/PENDIENTE.md](docs/PENDIENTE.md) | Qué falta para completar el MVP |
| [docs/DISTRIBUCION.md](docs/DISTRIBUCION.md) | Cómo llega el APK a los investigadores |
| [app/README.md](app/README.md) | Cómo correr la app y dónde vive cada restricción |
| [design/](design/) | El canvas de diseño del que sale la interfaz |

## Estructura

```
app/           cliente Flutter (móvil + web)
deploy/        despliegue con Docker: Postgres, panel web, TLS
design/        canvas de diseño, como referencia
docs/          notas por hito y decisiones
web-descarga/  página de descarga del APK
```

## Verificación

Cada push analiza y prueba la app en GitHub Actions — el equipo no tiene ancho de
banda para descargar el SDK de Flutter:

```bash
gh workflow run verificar.yml && gh run watch
```

Página de descarga del APK: **https://telestas.github.io/SIVAP/**

## Las reglas que todo cambio debe respetar

1. Ficha del paciente y datos clínicos son **entidades separadas**.
2. **Cegamiento**: el sistema solo conoce Protocolo A y Protocolo B. Nunca cuál es
   cuál. Hay una prueba automática que lo comprueba.
3. **Sin ediciones silenciosas**: toda corrección genera entrada de auditoría.
4. La captura se estructura **por eventos clínicos, no por calendario**.
5. Formularios definidos **como datos**, no como código.
6. Módulo de **asignación desacoplado** y ciego hacia adelante.
7. La **semilla** no vive en el repositorio ni en la app.
8. Multicéntrico: todo registro lleva **institución**.
9. **Minimización** de datos personales.
10. **Cifrado** obligatorio, en reposo y en tránsito.
11. Cada endpoint declara **qué rol** lo invoca.
12. **Offline-first real**.
13. Sin pacientes reales hasta la **aprobación del CEI**.
14. El **dato clínico manda** sobre la validación: los rangos avisan, no bloquean.
15. **Nada identificable** en el repositorio.

Detalle completo en [CLAUDE.md](CLAUDE.md).
