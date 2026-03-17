#!/usr/bin/env bash
# config.sh — read/write ~/.config/talc2/config.env
# shellcheck shell=bash
set -euo pipefail

TALC_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/talc2"
TALC_CONFIG_FILE="$TALC_CONFIG_DIR/config.env"

# Defaults
TALC_DOMAIN_SUFFIX='internal'
TALC_LOCAL_IP='auto'
TALC_CADDY_API='http://localhost:2019'
TALC_CERTS_DIR='/etc/caddy/certs'
TALC_ENABLE_TLS='true'

config::load() {
  if [[ -f $TALC_CONFIG_FILE ]]; then
    # shellcheck source=/dev/null
    source "$TALC_CONFIG_FILE"
  fi
}

config::write() {
  mkdir -p "$TALC_CONFIG_DIR"
  cat > "$TALC_CONFIG_FILE" <<EOF
# talc2 configuration — $(date '+%Y-%m-%d')
TALC_DOMAIN_SUFFIX='${TALC_DOMAIN_SUFFIX}'
TALC_LOCAL_IP='${TALC_LOCAL_IP}'
TALC_CADDY_API='${TALC_CADDY_API}'
TALC_CERTS_DIR='${TALC_CERTS_DIR}'
TALC_ENABLE_TLS='${TALC_ENABLE_TLS}'
EOF
}

config::init_defaults() {
  mkdir -p "$TALC_CONFIG_DIR"
  if [[ ! -f $TALC_CONFIG_FILE ]]; then
    config::write
  fi
}
