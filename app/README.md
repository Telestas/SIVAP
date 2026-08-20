# app · SIVAP (Flutter)

Cliente de captura del ensayo LIVERE. Captura por eventos clínicos, sin conexión,
con la base local cifrada. Sin backend todavía.

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

## Las pantallas

| Pantalla | Código |
|---|---|
| Acceso y rol | `features/auth/login_screen.dart` |
| Lista del recolector / cohorte del observador | `features/patients/patient_list_screen.dart` |
| Enrolamiento | `features/enrollment/enrollment_screen.dart` |
| Consentimiento | `features/consent/consent_screen.dart` |
| Línea de tiempo del paciente | `features/eventos/paciente_timeline_screen.dart` |
| Captura de un evento clínico | `features/eventos/evento_form_screen.dart` |
| Panel de administración | `features/admin/admin_dashboard_screen.dart` |

El canvas original está en [`../design/SIVAP.dc.html`](../design/SIVAP.dc.html). Ojo:
retrata el modelo anterior, con pestañas de día fijo. La línea de tiempo por fases lo
sustituye — ver `docs/REENCAMINAMIENTO.md`, paso 3.

## Dónde viven las restricciones no negociables

No son comentarios sueltos: cada una tiene un sitio concreto y una prueba.

| CLAUDE.md | Dónde se hace valer | Prueba |
|---|---|---|
| §1 ficha ≠ datos clínicos | `Patient` y `EventoClinico` separados; el evento solo guarda `patientId` | `test/restricciones_test.dart` |
| §2 cegamiento | `Protocolo` es A/B y no tiene campo que describa la rama | `test/cegamiento_test.dart` |
| §3 sin ediciones silenciosas | `EventoNoRepetible`; `corregirEventoRegistrado` exige motivo; disparadores en la base | `test/restricciones_test.dart` |
| §4 captura por eventos | `TipoEvento` con ocurrencias repetibles y fecha real; enrolar no pre-crea nada | idem |
| §5 formularios configurables | `EstudioFormDefinition` con los cuatro módulos del Anexo 4; la pantalla recorre la definición | idem |
| §8 multicéntrico | `Institucion` en ficha, evento e investigador; código con prefijo de centro | idem |
| §9 minimización | La ficha no admite carné ni dirección | idem |
| BASES §4 separación de funciones | La captura va por tipo de hito; el evaluador no ve la rama | idem |
| §6 asignación desacoplada | `AllocationStrategy` + `SequentialAllocation`; sin forma de ver la rama siguiente | idem |
| §7 semilla fuera del repositorio | `Seed.semillaDemostracion` está marcada como falsa | `test/cegamiento_test.dart` |
| §10 cifrado | SQLCipher, clave en Keystore/Keychain, `PRAGMA cipher_version` verificado | `test/almacen_test.dart` |
| §11 roles | `PermissionDenied` en el repositorio, no solo en la UI | `test/restricciones_test.dart` |
| §12 offline-first | no hay una sola llamada de red | — |
| §13 consentimiento | sin consentimiento no hay captura | `test/restricciones_test.dart` |
| §14 el dato manda | `fueraDeRango` avisa, nunca bloquea | idem |
| §15 nada identificable | datos de demostración inventados y marcados | `test/cegamiento_test.dart` |

Si una de esas pruebas falla, no es un test roto: es el ensayo dejando de ser válido.

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
- **Los rangos clínicos van vacíos** a propósito, y hay una prueba que falla si
  alguien los rellena: los anteriores eran de paciente ambulatorio y en UCI
  producirían avisos falsos constantes. Ver `../docs/RANGOS_PENDIENTES.md`.
- **La secuencia de aleatorización no está repartida por dispositivo.** Dos
  dispositivos sin conexión asignarían la misma posición. Es bloqueante para
  enrolar pacientes reales — ver `../docs/REENCAMINAMIENTO.md`.
- **El acceso es de demostración**: se elige la función al entrar. En producción
  viene del servidor con la credencial.
- **La semilla de aleatorización es de demostración** (`Seed.semillaAleatorizacion`).
  La del estudio real la fija el investigador principal una sola vez, antes del
  primer paciente, y va al acta. Cambiarla con pacientes ya enrolados invalida
  la trazabilidad de todo lo asignado.
- **El selector de rol en el acceso es de demostración.** En producción el rol
  llega del servidor con la credencial: un investigador no elige sus permisos.
