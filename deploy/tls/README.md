# tls

Aquí van el certificado y la clave que usa nginx. **Nada de esto se versiona**
salvo el guion y este archivo: una clave privada en un repositorio deja de ser
privada, aunque el repositorio sea privado y aunque se borre después.

```bash
./generar-certificado.sh sivap.hospital.local
```

Produce:

| Archivo | Qué es | Dónde va |
|---|---|---|
| `ca.crt` | Autoridad del estudio | Se instala en cada dispositivo que abra el panel |
| `ca.key` | Clave de la autoridad | **No sale de este servidor** |
| `sivap.crt` | Certificado del servidor | Lo lee nginx |
| `sivap.key` | Clave del servidor | Lo lee nginx |

El certificado del servidor caduca al año. Conviene apuntar la fecha: cuando
caduque, el panel deja de abrir y el motivo no es evidente si nadie lo espera.
Renovarlo es volver a correr el guion —reutiliza la autoridad, así que no hay
que reinstalar nada en los dispositivos— y recrear el contenedor.
