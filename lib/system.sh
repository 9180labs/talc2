#!/usr/bin/env bash
# system.sh — privilege escalation, pacman, systemctl helpers
# shellcheck shell=bash
set -euo pipefail

# ── privilege escalation ──────────────────────────────────────────────────────
PRIV=''

priv::detect() {
  if [[ -n $PRIV ]]; then return; fi
  if command -v sudo &>/dev/null; then
    PRIV=sudo
  elif command -v doas &>/dev/null; then
    PRIV=doas
  else
    ui::error "Neither sudo nor doas found. Please install one."
    exit 1
  fi
}

priv::exec() {
  priv::detect
  $PRIV "$@"
}

# Write content to a privileged file via a temp file
priv::write_file() {
  local path="$1"
  local content="$2"
  priv::detect
  local dir; dir="$(dirname "$path")"
  if [[ ! -d $dir ]]; then
    priv::exec mkdir -p "$dir"
  fi
  local tmp; tmp="$(mktemp)"
  printf '%s' "$content" > "$tmp"
  priv::exec cp "$tmp" "$path"
  priv::exec chmod 644 "$path"
  rm -f "$tmp"
}

# Read a file that may require privilege
priv::read_file() {
  local path="$1"
  if [[ -r $path ]]; then
    cat "$path"
  else
    priv::exec cat "$path"
  fi
}

priv::delete_file() {
  local path="$1"
  priv::exec rm -f "$path"
}

# ── pacman ────────────────────────────────────────────────────────────────────
pkg::installed() {
  local pkg="$1"
  pacman -Q "$pkg" &>/dev/null
}

pkg::install() {
  local pkg="$1"
  if pkg::installed "$pkg"; then
    ui::info "$pkg is already installed"
    return 0
  fi
  ui::spin "Installing $pkg" -- priv::exec pacman -S --needed --noconfirm "$pkg"
}

# ── systemctl ─────────────────────────────────────────────────────────────────
svc::running() {
  systemctl is-active --quiet "$1" 2>/dev/null
}

svc::enabled() {
  systemctl is-enabled --quiet "$1" 2>/dev/null
}

svc::start() {
  priv::exec systemctl start "$1"
}

svc::stop() {
  priv::exec systemctl stop "$1"
}

svc::restart() {
  priv::exec systemctl restart "$1"
}

svc::reload() {
  priv::exec systemctl reload "$1"
}

svc::enable() {
  priv::exec systemctl enable "$1"
}

svc::disable() {
  priv::exec systemctl disable "$1"
}

svc::daemon_reload() {
  priv::exec systemctl daemon-reload
}
