"""Credenciales y tokens de sesión."""

import hashlib
import secrets
from datetime import datetime, timedelta, timezone

from argon2 import PasswordHasher
from argon2.exceptions import VerifyMismatchError, VerificationError

# Argon2id, que es lo que recomienda hoy OWASP para contraseñas. Los parámetros
# por defecto de la biblioteca son razonables; subirlos endurece el servidor a
# costa de tiempo por inicio de sesión, que aquí ocurre pocas veces al día.
_hasher = PasswordHasher()


def cifrar_credencial(contrasena: str) -> str:
    return _hasher.hash(contrasena)


def verificar_credencial(hash_guardado: str, contrasena: str) -> bool:
    try:
        _hasher.verify(hash_guardado, contrasena)
        return True
    except (VerifyMismatchError, VerificationError):
        return False


def necesita_rehash(hash_guardado: str) -> bool:
    """Si el hash se hizo con parámetros más flojos que los actuales."""
    return _hasher.check_needs_rehash(hash_guardado)


def nuevo_token() -> tuple[str, str]:
    """Devuelve (token, huella). El token se entrega una vez y no se guarda.

    En la base solo queda la huella: si alguien lee la tabla de sesiones, no
    puede suplantar a nadie. Es el mismo motivo por el que no se guardan
    contraseñas en claro.
    """
    token = secrets.token_urlsafe(32)
    return token, huella(token)


def huella(token: str) -> str:
    return hashlib.sha256(token.encode()).hexdigest()


def caducidad(horas: int) -> datetime:
    return datetime.now(timezone.utc) + timedelta(hours=horas)
