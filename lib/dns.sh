#!/usr/bin/env bash
# dns.sh — dnsmasq + systemd-resolved configuration
# shellcheck shell=bash
set -euo pipefail

DNSMASQ_TALC_CONF='/etc/dnsmasq.d/talc.conf'
DNSMASQ_MAIN_CONF='/etc/dnsmasq.conf'
RESOLVED_TALC_CONF='/etc/systemd/resolved.conf.d/talc.conf'
DNSMASQ_PORT=5335

# dns::configure LOCAL_IP DOMAIN_SUFFIX
dns::configure() {
  local local_ip="$1" suffix="$2"

  dns::_preflight

  # Enable conf-dir in main dnsmasq.conf if needed
  dns::_enable_conf_dir

  # Write dnsmasq wildcard config
  priv::write_file "$DNSMASQ_TALC_CONF" "$(dns::_dnsmasq_config "$local_ip" "$suffix")"

  # Write systemd-resolved forwarding config
  priv::write_file "$RESOLVED_TALC_CONF" "$(dns::_resolved_config "$suffix")"

  svc::daemon_reload
  svc::restart systemd-resolved
}

# dns::reload — restart/start dnsmasq
dns::reload() {
  if ! command -v dnsmasq &>/dev/null; then
    ui::error "dnsmasq is not installed"
    return 1
  fi
  if svc::running dnsmasq; then
    ui::spin "Restarting dnsmasq" -- svc::restart dnsmasq
  else
    ui::spin "Starting dnsmasq" -- svc::start dnsmasq
  fi
}

# dns::status — print status info (used by talc status)
dns::status() {
  local installed running enabled configured port_ok

  command -v dnsmasq &>/dev/null && installed=true || installed=false
  svc::running  dnsmasq && running=true  || running=false
  svc::enabled  dnsmasq && enabled=true  || enabled=false
  [[ -f $DNSMASQ_TALC_CONF ]] && configured=true || configured=false
  ss -tulpn 2>/dev/null | grep -q "127.0.0.1:${DNSMASQ_PORT} " && port_ok=true || port_ok=false

  local res_running res_enabled res_configured
  svc::running  systemd-resolved && res_running=true  || res_running=false
  svc::enabled  systemd-resolved && res_enabled=true  || res_enabled=false
  [[ -f $RESOLVED_TALC_CONF ]] && res_configured=true || res_configured=false

  printf '\n'
  ui::header "DNS"
  printf '\n'
  ui::status_row "dnsmasq installed"  ""       "$installed"
  ui::status_row "dnsmasq running"    ""       "$running"
  ui::status_row "dnsmasq enabled"    ""       "$enabled"
  ui::status_row "talc config"        ""       "$configured"
  ui::status_row "port $DNSMASQ_PORT" ""       "$port_ok"
  printf '\n'
  ui::header "systemd-resolved"
  printf '\n'
  ui::status_row "running"            ""       "$res_running"
  ui::status_row "enabled"            ""       "$res_enabled"
  ui::status_row "talc config"        ""       "$res_configured"
}

# dns::teardown
dns::teardown() {
  local errors=()

  [[ -f $DNSMASQ_TALC_CONF ]]  && { priv::delete_file "$DNSMASQ_TALC_CONF"  || errors+=("dnsmasq config"); }
  [[ -f $RESOLVED_TALC_CONF ]] && { priv::delete_file "$RESOLVED_TALC_CONF" || errors+=("resolved config"); }

  svc::running dnsmasq  && { priv::exec systemctl stop    dnsmasq || errors+=("stop dnsmasq"); }
  svc::enabled dnsmasq  && { priv::exec systemctl disable dnsmasq || errors+=("disable dnsmasq"); }

  svc::daemon_reload || true
  svc::running systemd-resolved && { priv::exec systemctl restart systemd-resolved || errors+=("restart resolved"); }

  if (( ${#errors[@]} > 0 )); then
    ui::warn "Some teardown steps failed: ${errors[*]}"
  fi
}

# ── private helpers ───────────────────────────────────────────────────────────

dns::_preflight() {
  command -v dnsmasq &>/dev/null || { ui::error "dnsmasq is not installed"; return 1; }
  svc::running systemd-resolved || {
    ui::error "systemd-resolved is not running. Start it first: sudo systemctl start systemd-resolved"
    return 1
  }
  dns::_check_port
}

dns::_check_port() {
  local listeners
  listeners="$(ss -tulpn 2>/dev/null | grep ":${DNSMASQ_PORT} " || true)"
  [[ -z $listeners ]] && return 0

  # Only conflicts on 127.0.0.1
  local local_listeners
  local_listeners="$(grep "127\.0\.0\.1:${DNSMASQ_PORT} " <<< "$listeners" || true)"
  [[ -z $local_listeners ]] && return 0

  # If it's dnsmasq itself, that's fine
  grep -q 'dnsmasq' <<< "$local_listeners" && return 0

  ui::error "Port $DNSMASQ_PORT is already in use on 127.0.0.1 by another process."
  ui::error "Stop it before running setup."
  return 1
}

dns::_enable_conf_dir() {
  [[ -f $DNSMASQ_MAIN_CONF ]] || return 0
  local content
  content="$(priv::read_file "$DNSMASQ_MAIN_CONF")"

  # Already enabled?
  grep -q '^conf-dir=/etc/dnsmasq\.d' <<< "$content" && return 0

  if grep -q '^#conf-dir=/etc/dnsmasq\.d' <<< "$content"; then
    # Uncomment existing line
    local updated
    updated="${content//#conf-dir=\/etc\/dnsmasq.d/conf-dir=\/etc\/dnsmasq.d}"
    priv::write_file "$DNSMASQ_MAIN_CONF" "$updated"
  else
    # Append
    local appended
    appended="${content}

# Added by talc2 — enables loading /etc/dnsmasq.d/*.conf
conf-dir=/etc/dnsmasq.d/,*.conf
"
    priv::write_file "$DNSMASQ_MAIN_CONF" "$appended"
  fi
}

dns::_dnsmasq_config() {
  local local_ip="$1" suffix="$2"
  cat <<EOF
# Managed by talc2
# Architecture: systemd-resolved (port 53) forwards .${suffix} → dnsmasq (port ${DNSMASQ_PORT})
port=${DNSMASQ_PORT}
listen-address=127.0.0.1
bind-interfaces

# Don't read /etc/resolv.conf (systemd-resolved handles forwarding)
no-resolv

# Wildcard DNS: all *.${suffix} resolve to the LAN IP
address=/.${suffix}/${local_ip}
EOF
}

dns::_resolved_config() {
  local suffix="$1"
  cat <<EOF
# Managed by talc2
# Forward all .${suffix} DNS queries to dnsmasq on localhost:${DNSMASQ_PORT}
[Resolve]
DNS=127.0.0.1:${DNSMASQ_PORT}
Domains=~${suffix}
EOF
}
