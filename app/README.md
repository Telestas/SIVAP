# app · SIVAP (Flutter)

Cliente de captura de datos del estudio. Hito 1: **interfaz completa + capa de
datos local**, sin backend.

## Correr

Faltan las carpetas de plataforma (`android/`, `ios/`, `web/`): las genera el
propio Flutter y no se pudieron crear aquí (ver la limitación al final de
[`../docs/HITO_1.md`](../docs/HITO_1.md)). Una sola vez, dentro de `app/`:

```bash
flutter create .    # añade android/ ios/ web/ sin tocar lib/, test/ ni pubspec
```

Después, lo de siempre:

```bash
flutter pub get
flutter run            # dispositivo o emulador
flutter run -d chrome  # web (útil para revisar el panel de administración)
flutter test
flutter analyze
```

Sin dependencias de terceros: solo el SDK de Flutter y `flutter_lints`. Es
deliberado — la app tiene que poder compilarse con conectividad intermitente.

## Cómo está organizado

```
lib/
  core/            tokens de diseño, tema, formato, widgets compartidos
  domain/models/   ficha, visita, definición de formulario, auditoría, roles
  domain/repositories/  interfaz StudyRepository (lo que ven las pantallas)
  data/local/      implementación en memoria + datos de demostración
  data/allocation/ módulo de asignación de protocolo (aislado y reemplazable)
  features/        una carpeta por pantalla del diseño
```

Las pantallas nunca hablan con el almacén directamente, solo con
`StudyRepository`. Cambiar "en memoria" por "SQLite cifrado + cola de
sincronización" no toca ninguna pantalla.

## Las siete pantallas del diseño

| # | Diseño | Código |
|---|---|---|
| 01 | Acceso y rol | `features/auth/login_screen.dart` |
| 02 | Lista — recolector | `features/patients/patient_list_screen.dart` |
| 03 | Lista — observador | la misma, en modo solo lectura |
| 04 | Enrolamiento | `features/enrollment/enrollment_screen.dart` |
| 05 | Captura de visita | `features/visits/visit_capture_screen.dart` |
| 06 | Consentimiento | `features/consent/consent_screen.dart` |
| 07 | Panel de administración | `features/admin/admin_dashboard_screen.dart` |

El canvas original está en [`../design/SIVAP.dc.html`](../design/SIVAP.dc.html).

## Dónde viven las restricciones no negociables

No son comentarios sueltos: cada una tiene un sitio concreto y una prueba.

| CLAUDE.md | Dónde se hace valer | Prueba |
|---|---|---|
| §1 ficha ≠ visita | `Patient` y `Visit` son clases separadas; `Visit` solo guarda `patientId` | `test/restricciones_test.dart` |
| §2 sin ediciones silenciosas | `SilentEditRejected`; `corregirVisitaEnviada` exige motivo | idem |
| §3 formularios configurables | `VisitFormDefinition`; la pantalla de captura recorre la definición | idem |
| §4 asignación desacoplada | `AllocationStrategy` + `SequentialAllocation` sobre una `AllocationSequence` generada desde semilla | idem |
| §6 roles y permisos | `PermissionDenied` en el repositorio, no solo en la UI | idem |
| §7 offline-first | no hay una sola llamada de red en el hito | — |
| §8 consentimiento | `StudyConfig.consentimientoAprobadoPorCei`; sin consentimiento no hay captura | idem |

Si una de esas pruebas falla, no es un test roto: es el estudio dejando de ser
válido.

## Almacenamiento local

| Plataforma | Almacén | Cifrado |
|---|---|---|
| Android / iOS / escritorio | SQLite + SQLCipher, archivo en el directorio de la app | Sí, AES-256 |
| Navegador | En memoria | **No** — y la app lo avisa en pantalla |

La clave la genera el dispositivo la primera vez y vive en el Keystore de
Android o el Keychain de iOS. **Nunca está en el código**: una clave dentro del
.apk no cifra nada, porque va en el mismo archivo que cualquiera puede abrir.

Al abrir, la app comprueba `PRAGMA cipher_version` y **se niega a arrancar** si
lo que se cargó no es SQLCipher. Sin esa comprobación, un fallo de empaquetado
dejaría la base en claro y nadie se enteraría.

En el navegador no hay cifrado y no se finge que lo haya: no existe archivo que
cifrar, y guardar la clave en el propio navegador no protege de nadie. La web es
el panel de administración y su sitio es leer del servidor.

Demostración y producción son **archivos distintos** (`sivap_demo.db` y
`sivap.db`), no un modo dentro del mismo archivo. Se elige con `modoAlmacen` en
`lib/main.dart`. Así un paciente inventado no puede acabar nunca en el dataset
del estudio.

## Lo que este hito NO hace

- **Sin backend ni sincronización**: el estado "en cola" se simula con un
  interruptor para poder enseñar el comportamiento offline.
- **Sin exportación**: el .xlsx se genera en el servidor (openpyxl), hito posterior.
- **Los campos de visita son un borrador** (BASES §5). Están tomados de la
  maqueta; el listado real lo debe entregar el equipo médico. Cambiarlos es
  editar `Seed.formulario`, no tocar pantallas.
- **La semilla de aleatorización es de demostración** (`Seed.semillaAleatorizacion`).
  La del estudio real la fija el investigador principal una sola vez, antes del
  primer paciente, y va al acta. Cambiarla con pacientes ya enrolados invalida
  la trazabilidad de todo lo asignado.
- **El selector de rol en el acceso es de demostración.** En producción el rol
  llega del servidor con la credencial: un investigador no elige sus permisos.
