# Repository Guidelines

## Estructura del proyecto

SIVAP combina un cliente Flutter offline-first, una API FastAPI y PostgreSQL. La app
vive en `app/`: `lib/` se divide en `core/`, `domain/`, `data/` y `features/`; las
pruebas están en `test/` y los recursos en `assets/`. El servicio está en
`api/sivap/`, sus pruebas en `api/pruebas/` y migraciones SQL en `api/migraciones/`.
`deploy/` contiene Compose y TLS; `docs/` conserva decisiones. Lea `CLAUDE.md` antes
de modificar código: define las restricciones clínicas y de seguridad.

## Desarrollo, compilación y pruebas

Ejecute los comandos desde el directorio correspondiente.

```bash
cd app && flutter pub get && flutter analyze  # dependencias y análisis estático
cd app && flutter test                         # pruebas Dart/Flutter
cd app && flutter run -d chrome                # cliente web para revisión
cd api && pip install -e '.[pruebas]'          # API y dependencias de prueba
cd api && python -m pytest pruebas -q          # pruebas contra PostgreSQL real
```

Para la API, inicie PostgreSQL como indica `api/README.md` y defina `DATABASE_URL`.
Si faltan plataformas Flutter, ejecute una vez `cd app && flutter create .` sin tocar
`lib/`, `test/` ni `pubspec.yaml`. Para despliegue, copie `.env.example` a `.env`,
mantenga secretos fuera de Git y use `docker compose up -d` desde `deploy/`.

## Estilo y convenciones

El código, comentarios y documentación van en español. Use dos espacios en Dart y
ejecute `dart format` y `flutter analyze`. Use `snake_case.dart` para archivos,
`PascalCase` para clases/enums y `camelCase` para miembros. En Python siga PEP 8 y
`snake_case`. No introduzca un ORM: el SQL debe ser explícito y legible.

## Pruebas y reglas clínicas

Agregue o ajuste una prueba al cambiar comportamiento. Las pruebas de app usan
`*_test.dart`; las de API, `test_*.py`. Ejecute el conjunto pertinente y el análisis
antes de abrir un PR. Nunca debilite pruebas de cegamiento, auditoría, consentimiento,
roles o cifrado.

Mantenga ficha de identidad y datos clínicos separados; use únicamente `Protocolo A`
y `Protocolo B`; modele capturas por eventos reales, no por días. No versionar datos
identificables, credenciales, semillas reales, claves TLS ni copias de seguridad.

## Commits y pull requests

El historial usa mensajes breves en español, a menudo con ámbito: `app: ...`,
`api: ...`, `docs: ...`. Haga commits pequeños y coherentes. En cada PR explique el
cambio y su impacto, enlace la decisión o issue aplicable, indique verificaciones y
adjunte capturas para cambios visuales. Destaque cambios de esquema, migración o
despliegue.
