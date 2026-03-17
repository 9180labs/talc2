#!/usr/bin/env bash
# ui.sh — gum-based TUI helpers for talc2
# shellcheck shell=bash

# ── gum availability ──────────────────────────────────────────────────────────
_GUM_AVAILABLE=''
_gum_available() {
  if [[ -z $_GUM_AVAILABLE ]]; then
    if command -v gum &>/dev/null; then
      _GUM_AVAILABLE=1
    else
      _GUM_AVAILABLE=0
    fi
  fi
  [[ $_GUM_AVAILABLE == 1 ]]
}

# ── spinners ──────────────────────────────────────────────────────────────────
# ui::spin TITLE -- COMMAND [ARGS...]
# Prints a styled label then runs COMMAND directly (functions and binaries both work).
ui::spin() {
  local title="$1"; shift
  [[ ${1:-} == '--' ]] && shift
  if _gum_available; then
    gum style --foreground 212 "  ◆ $title"
  else
    printf '  » %s...\n' "$title"
  fi
  "$@"
}

# ── confirmations ─────────────────────────────────────────────────────────────
# ui::confirm PROMPT — returns 0 (yes) or 1 (no)
ui::confirm() {
  local prompt="$1"
  if _gum_available; then
    gum confirm "$prompt"
  else
    read -r -p "$prompt [y/N] " ans
    [[ ${ans,,} == y* ]]
  fi
}

# ui::confirm_danger PROMPT — styled red for destructive actions
ui::confirm_danger() {
  local prompt="$1"
  if _gum_available; then
    gum confirm \
      --prompt.foreground="9" \
      --selected.background="9" \
      "$prompt"
  else
    read -r -p "$(printf '\033[31m%s\033[0m [y/N] ' "$prompt")" ans
    [[ ${ans,,} == y* ]]
  fi
}

# ── inputs ────────────────────────────────────────────────────────────────────
# ui::input PROMPT [PLACEHOLDER] [VALUE] — prints the entered value
ui::input() {
  local prompt="$1"
  local placeholder="${2:-}"
  local value="${3:-}"
  if _gum_available; then
    local args=(--prompt "$prompt: " --placeholder "$placeholder")
    [[ -n $value ]] && args+=(--value "$value")
    gum input "${args[@]}"
  else
    local ans
    if [[ -n $value ]]; then
      read -r -p "$prompt [$value]: " ans
      printf '%s' "${ans:-$value}"
    else
      read -r -p "$prompt: " ans
      printf '%s' "$ans"
    fi
  fi
}

# ── table output ──────────────────────────────────────────────────────────────
# ui::table — reads CSV from stdin and renders as a table
ui::table() {
  if _gum_available; then
    gum table --separator $'\t'
  else
    column -t -s $'\t'
  fi
}

# ── styled text ───────────────────────────────────────────────────────────────
# ui::header TEXT
ui::header() {
  if _gum_available; then
    gum style \
      --border rounded \
      --border-foreground 212 \
      --padding "0 1" \
      --bold \
      "$1"
  else
    printf '\033[1;36m%s\033[0m\n' "$1"
    printf '%s\n' "$(printf '─%.0s' $(seq 1 ${#1}))"
  fi
}

# ui::success TEXT
ui::success() {
  if _gum_available; then
    gum style --foreground 10 "✓ $1"
  else
    printf '\033[32m✓ %s\033[0m\n' "$1"
  fi
}

# ui::error TEXT
ui::error() {
  if _gum_available; then
    gum style --foreground 9 "✗ $1" >&2
  else
    printf '\033[31m✗ %s\033[0m\n' "$1" >&2
  fi
}

# ui::warn TEXT
ui::warn() {
  if _gum_available; then
    gum style --foreground 11 "⚠ $1" >&2
  else
    printf '\033[33m⚠ %s\033[0m\n' "$1" >&2
  fi
}

# ui::info TEXT
ui::info() {
  if _gum_available; then
    gum style --foreground 14 "  $1"
  else
    printf '  %s\n' "$1"
  fi
}

# ui::status_row LABEL VALUE OK_BOOL
# Renders a status line: "  LABEL    ✓ / ✗"
ui::status_row() {
  local label="$1"
  local value="$2"   # the check/cross or custom text
  local ok="$3"      # "true" or "false" — controls color
  local icon color
  if [[ $ok == true ]]; then
    icon='✓'; color=10
  else
    icon='✗'; color=9
  fi
  if _gum_available; then
    printf '  %-20s %s\n' "$label" "$(gum style --foreground "$color" "$icon $value")"
  else
    local esc
    esc=$( [[ $ok == true ]] && printf '\033[32m' || printf '\033[31m' )
    printf '  %-20s %s%s %s\033[0m\n' "$label" "$esc" "$icon" "$value"
  fi
}
