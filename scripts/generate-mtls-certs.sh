#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CA_DIR="${ROOT_DIR}/certs/ca"
CLIENT_DIR="${ROOT_DIR}/certs/clients"

mkdir -p "${CA_DIR}" "${CLIENT_DIR}"
umask 077

CA_KEY="${CA_DIR}/ca.key"
CA_CERT="${CA_DIR}/ca.crt"
CA_SERIAL="${CA_DIR}/ca.srl"
CLIENT_KEY="${CLIENT_DIR}/site-client.key"
CLIENT_CSR="${CLIENT_DIR}/site-client.csr"
CLIENT_CERT="${CLIENT_DIR}/site-client.crt"
CLIENT_EXT="${CLIENT_DIR}/site-client.ext"

openssl genrsa -out "${CA_KEY}" 4096
openssl req \
  -x509 \
  -new \
  -sha256 \
  -days 3650 \
  -key "${CA_KEY}" \
  -out "${CA_CERT}" \
  -subj "/C=JP/O=bmuscle/CN=vpn-mtls-ca"

openssl genrsa -out "${CLIENT_KEY}" 2048
openssl req \
  -new \
  -key "${CLIENT_KEY}" \
  -out "${CLIENT_CSR}" \
  -subj "/C=JP/O=bmuscle/CN=site-client"

cat > "${CLIENT_EXT}" <<'EXT'
basicConstraints=CA:FALSE
keyUsage=digitalSignature,keyEncipherment
extendedKeyUsage=clientAuth
subjectKeyIdentifier=hash
authorityKeyIdentifier=keyid,issuer
EXT

openssl x509 \
  -req \
  -in "${CLIENT_CSR}" \
  -CA "${CA_CERT}" \
  -CAkey "${CA_KEY}" \
  -CAcreateserial \
  -CAserial "${CA_SERIAL}" \
  -out "${CLIENT_CERT}" \
  -days 825 \
  -sha256 \
  -extfile "${CLIENT_EXT}"

rm -f "${CLIENT_CSR}" "${CLIENT_EXT}"

chmod 600 "${CA_KEY}" "${CLIENT_KEY}"
chmod 644 "${CA_CERT}" "${CLIENT_CERT}"

echo "Generated:"
echo "  CA cert      : ${CA_CERT}"
echo "  CA key       : ${CA_KEY}"
echo "  Client cert  : ${CLIENT_CERT}"
echo "  Client key   : ${CLIENT_KEY}"
