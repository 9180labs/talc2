#!/usr/bin/env bash
# storage.sh — TSV-based domain persistence
# Fields: name <TAB> port <TAB> ip <TAB> updated_at
# shellcheck shell=bash
set -euo pipefail

TALC_DOMAINS_FILE="${TALC_CONFIG_DIR:-$HOME/.config/talc2}/domains.tsv"
TALC_DOMAINS_LOCK="${TALC_CONFIG_DIR:-$HOME/.config/talc2}/domains.lock"

storage::init() {
  mkdir -p "$(dirname "$TALC_DOMAINS_FILE")"
  [[ -f $TALC_DOMAINS_FILE ]] || touch "$TALC_DOMAINS_FILE"
}

# storage::all — print all rows (tab-separated)
storage::all() {
  storage::init
  cat "$TALC_DOMAINS_FILE"
}

# storage::find NAME — print the matching row or empty
storage::find() {
  local name="$1"
  storage::init
  grep -m1 $'^'"$name"$'\t' "$TALC_DOMAINS_FILE" 2>/dev/null || true
}

# storage::exists NAME
storage::exists() {
  local name="$1"
  [[ -n $(storage::find "$name") ]]
}

# storage::add NAME PORT IP
storage::add() {
  local name="$1" port="$2" ip="${3:-127.0.0.1}"
  storage::init
  if storage::exists "$name"; then
    ui::error "Domain '$name' already exists"
    return 1
  fi
  local now; now="$(date '+%Y-%m-%d %H:%M')"
  (
    flock -x 200
    printf '%s\t%s\t%s\t%s\n' "$name" "$port" "$ip" "$now" >> "$TALC_DOMAINS_FILE"
  ) 200>"$TALC_DOMAINS_LOCK"
}

# storage::remove NAME
storage::remove() {
  local name="$1"
  storage::init
  if ! storage::exists "$name"; then
    ui::error "Domain '$name' not found"
    return 1
  fi
  (
    flock -x 200
    local tmp; tmp="$(mktemp)"
    grep -v $'^'"$name"$'\t' "$TALC_DOMAINS_FILE" > "$tmp" || true
    mv "$tmp" "$TALC_DOMAINS_FILE"
  ) 200>"$TALC_DOMAINS_LOCK"
}

# storage::update NAME [PORT] [IP]
# Pass empty string to keep existing value
storage::update() {
  local name="$1" new_port="$2" new_ip="$3"
  storage::init
  local row; row="$(storage::find "$name")"
  if [[ -z $row ]]; then
    ui::error "Domain '$name' not found"
    return 1
  fi
  local old_port old_ip old_updated
  IFS=$'\t' read -r _ old_port old_ip old_updated <<< "$row"
  local port="${new_port:-$old_port}"
  local ip="${new_ip:-$old_ip}"
  local now; now="$(date '+%Y-%m-%d %H:%M')"
  (
    flock -x 200
    local tmp; tmp="$(mktemp)"
    grep -v $'^'"$name"$'\t' "$TALC_DOMAINS_FILE" > "$tmp" || true
    printf '%s\t%s\t%s\t%s\n' "$name" "$port" "$ip" "$now" >> "$tmp"
    mv "$tmp" "$TALC_DOMAINS_FILE"
  ) 200>"$TALC_DOMAINS_LOCK"
}

# storage::clear — remove all domains
storage::clear() {
  (
    flock -x 200
    : > "$TALC_DOMAINS_FILE"
  ) 200>"$TALC_DOMAINS_LOCK"
}

# storage::count
storage::count() {
  storage::all | wc -l
}
