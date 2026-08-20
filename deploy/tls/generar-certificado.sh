#!/usr/bin/env bash
#
# Genera el certificado TLS del panel de SIVAP para una red interna.
#
# Crea dos cosas:
#
#   ca.crt / ca.key    Autoridad propia del estudio. `ca.crt` es lo que hay que
#                      instalar UNA vez en cada equipo o teléfono que vaya a
#                      abrir el panel. `ca.key` no sale nunca de este servidor.
#
#   sivap.crt / .key   Certificado del servidor, firmado por esa autoridad.
#                      Lo usa nginx. Caduca al año: hay que repetirlo.
#
# Si el servidor tuviera un nombre público y acceso a internet, esto sobra:
# ahí lo correcto es un certificado de Let's Encrypt, que además se renueva
# solo. Este guion es para el caso de red de hospital sin nada de eso.

set -euo pipefail
cd "$(dirname "$0")"

DOMINIO="${1:-${SIVAP_DOMINIO:-sivap.local}}"
DIAS_SERVIDOR=365
DIAS_CA=3650

echo "Generando certificado para: $DOMINIO"

# ── Autoridad ────────────────────────────────────────────────────────
# Se reutiliza si ya existe: crear una autoridad nueva obligaría a reinstalar
# el certificado raíz en todos los dispositivos otra vez.
if [[ -f ca.key && -f ca.crt ]]; then
  echo "Autoridad existente: se reutiliza (ca.crt)"
else
  echo "Creando autoridad nueva"
  openssl genrsa -out ca.key 4096
  openssl req -x509 -new -nodes -key ca.key -sha256 -days "$DIAS_CA" -out ca.crt \
    -subj "/C=CU/O=Estudio SIVAP/CN=Autoridad interna SIVAP"
fi

# ── Certificado del servidor ─────────────────────────────────────────
# El SAN es obligatorio: los navegadores actuales ignoran el CN y sin SAN
# rechazan el certificado aunque el nombre coincida.
openssl genrsa -out sivap.key 2048
openssl req -new -key sivap.key -out sivap.csr \
  -subj "/C=CU/O=Estudio SIVAP/CN=$DOMINIO"

cat > sivap.ext <<EOF
authorityKeyIdentifier=keyid,issuer
basicConstraints=CA:FALSE
keyUsage=digitalSignature,keyEncipherment
extendedKeyUsage=serverAuth
subjectAltName=DNS:$DOMINIO,DNS:localhost,IP:127.0.0.1
EOF

openssl x509 -req -in sivap.csr -CA ca.crt -CAkey ca.key -CAcreateserial \
  -out sivap.crt -days "$DIAS_SERVIDOR" -sha256 -extfile sivap.ext

rm -f sivap.csr sivap.ext
chmod 600 ca.key sivap.key

echo
echo "Listo. Caduca el: $(openssl x509 -enddate -noout -in sivap.crt | cut -d= -f2)"
echo
echo "Ahora:"
echo "  1. Instalar ca.crt como certificado raíz de confianza en cada"
echo "     dispositivo que vaya a abrir el panel."
echo "  2. Que $DOMINIO resuelva a este servidor (DNS del hospital o"
echo "     /etc/hosts en cada equipo)."
echo "  3. docker compose up -d --force-recreate web"
