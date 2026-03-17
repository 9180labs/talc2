#!/usr/bin/env bash
# certs.sh — wildcard TLS certificate generation via openssl
# shellcheck shell=bash
set -euo pipefail

CERTS_VALIDITY_DAYS=825

# certs::generate FULL_DOMAIN — writes cert + key under TALC_CERTS_DIR
# prints "CERT_PATH KEY_PATH" on stdout
certs::generate() {
  local domain="$1"
  local safe; safe="${domain//[^a-zA-Z0-9._-]/_}"
  local cert_path="${TALC_CERTS_DIR}/${safe}.crt"
  local key_path="${TALC_CERTS_DIR}/${safe}.key"

  certs::_ensure_dir

  local tmp_key tmp_cert
  tmp_key="$(mktemp)"
  tmp_cert="$(mktemp)"

  # Generate key + self-signed cert with SAN for apex + wildcard
  openssl req -x509 -newkey rsa:2048 -nodes \
    -keyout "$tmp_key" \
    -out    "$tmp_cert" \
    -days   "$CERTS_VALIDITY_DAYS" \
    -subj   "/CN=${domain}" \
    -addext "subjectAltName=DNS:${domain},DNS:*.${domain}" \
    2>/dev/null

  priv::exec cp "$tmp_cert" "$cert_path"
  priv::exec cp "$tmp_key"  "$key_path"
  priv::exec chmod 644 "$cert_path"
  priv::exec chmod 600 "$key_path"
  rm -f "$tmp_key" "$tmp_cert"

  printf '%s %s\n' "$cert_path" "$key_path"
}

certs::exists() {
  local domain="$1"
  local safe; safe="${domain//[^a-zA-Z0-9._-]/_}"
  [[ -f "${TALC_CERTS_DIR}/${safe}.crt" && -f "${TALC_CERTS_DIR}/${safe}.key" ]]
}

certs::remove() {
  local domain="$1"
  local safe; safe="${domain//[^a-zA-Z0-9._-]/_}"
  priv::exec rm -f "${TALC_CERTS_DIR}/${safe}.crt" "${TALC_CERTS_DIR}/${safe}.key" || true
}

certs::_ensure_dir() {
  if [[ ! -d $TALC_CERTS_DIR ]]; then
    priv::exec mkdir -p "$TALC_CERTS_DIR"
    priv::exec chmod 755 "$TALC_CERTS_DIR"
  fi
}
