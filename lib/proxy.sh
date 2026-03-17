#!/usr/bin/env bash
# proxy.sh — Caddy reverse proxy management
# Tries Caddy Admin API first; falls back to Caddyfile.
# shellcheck shell=bash
set -euo pipefail

CADDYFILE='/etc/caddy/Caddyfile'
CADDY_MARKER_START='# --- Managed by talc2 ---'
CADDY_MARKER_END='# --- End talc2 ---'

# ── public interface ──────────────────────────────────────────────────────────

# proxy::add_route DOMAIN PORT IP [CERT_PATH KEY_PATH]
proxy::add_route() {
  local domain="$1" port="$2" ip="${3:-127.0.0.1}"
  local cert_path="${4:-}" key_path="${5:-}"

  command -v caddy &>/dev/null || { ui::error "Caddy is not installed"; return 1; }

  if proxy::_api_reachable; then
    proxy::_api_ensure_server
    proxy::_api_add_route "$domain" "$port" "$ip"
    [[ -n $cert_path && -n $key_path ]] && proxy::_api_load_cert "$cert_path" "$key_path"
  else
    proxy::_file_add_route "$domain" "$port" "$ip" "$cert_path" "$key_path"
    proxy::_file_reload_or_warn
  fi
}

# proxy::remove_route DOMAIN
proxy::remove_route() {
  local domain="$1"
  command -v caddy &>/dev/null || { ui::error "Caddy is not installed"; return 1; }

  if proxy::_api_reachable; then
    proxy::_api_remove_route "$domain"
  else
    proxy::_file_remove_route "$domain"
    proxy::_file_reload_or_warn
  fi
}

# proxy::status — print Caddy status block
proxy::status() {
  local installed running enabled api_ok
  command -v caddy &>/dev/null && installed=true || installed=false
  svc::running caddy  && running=true  || running=false
  svc::enabled caddy  && enabled=true  || enabled=false
  proxy::_api_reachable && api_ok=true || api_ok=false

  printf '\n'
  ui::header "Caddy"
  printf '\n'
  ui::status_row "installed"    "" "$installed"
  ui::status_row "running"      "" "$running"
  ui::status_row "enabled"      "" "$enabled"
  ui::status_row "API reachable" "" "$api_ok"
}

# proxy::teardown — remove talc2 section from Caddyfile + reload
proxy::teardown() {
  [[ -f $CADDYFILE ]] || return 0
  local content
  content="$(priv::read_file "$CADDYFILE")"
  local new_content
  new_content="$(proxy::_strip_talc_section "$content")"
  if [[ -z ${new_content// /} ]]; then
    new_content="# Caddyfile\n"
  fi
  priv::write_file "$CADDYFILE" "$new_content"
  svc::running caddy && { priv::exec systemctl reload caddy || true; }
}

# ── Caddy Admin API ───────────────────────────────────────────────────────────

proxy::_api_reachable() {
  curl -sf --max-time 2 "${TALC_CADDY_API}/config/" &>/dev/null
}

proxy::_api_ensure_server() {
  local url="${TALC_CADDY_API}/config/apps/http/servers/talc"
  local status
  status="$(curl -so /dev/null -w '%{http_code}' --max-time 2 "$url")"
  if [[ $status == 404 ]]; then
    curl -sf -X POST "$url" \
      -H 'Content-Type: application/json' \
      -d '{"listen":[":80",":443"],"routes":[]}' &>/dev/null
  else
    # Ensure :443 is listed
    local listen
    listen="$(curl -sf --max-time 2 "$url" | python3 -c "import sys,json; d=json.load(sys.stdin); print(json.dumps(d.get('listen',[])))" 2>/dev/null || echo '[]')"
    if ! grep -q '":443"' <<< "$listen"; then
      curl -sf -X PATCH "${TALC_CADDY_API}/config/apps/http/servers/talc/listen" \
        -H 'Content-Type: application/json' \
        -d "$(python3 -c "import sys,json; d=json.loads(sys.argv[1]); d.append(':443'); print(json.dumps(d))" "$listen")" &>/dev/null || true
    fi
  fi
}

proxy::_api_add_route() {
  local domain="$1" port="$2" ip="$3"
  local payload
  payload="$(cat <<JSON
{
  "match":[{"host":["${domain}","*.${domain}"]}],
  "handle":[{"handler":"reverse_proxy","upstreams":[{"dial":"${ip}:${port}"}]}]
}
JSON
)"
  local resp
  resp="$(curl -sf -o /dev/null -w '%{http_code}' \
    -X POST "${TALC_CADDY_API}/config/apps/http/servers/talc/routes" \
    -H 'Content-Type: application/json' \
    -d "$payload")"
  [[ $resp =~ ^2 ]] || { ui::error "Caddy API error adding route: HTTP $resp"; return 1; }
}

proxy::_api_remove_route() {
  local domain="$1"
  local routes_url="${TALC_CADDY_API}/config/apps/http/servers/talc/routes"
  local routes
  routes="$(curl -sf --max-time 2 "$routes_url" 2>/dev/null || echo '[]')"

  # Find the index of the route for this domain
  local idx
  idx="$(python3 - "$domain" <<'PYEOF'
import sys, json
domain = sys.argv[1]
routes = json.load(sys.stdin)
for i, r in enumerate(routes):
    hosts = r.get('match', [{}])[0].get('host', [])
    if domain in hosts or f'*.{domain}' in hosts:
        print(i)
        sys.exit(0)
sys.exit(1)
PYEOF
  <<< "$routes")" || { ui::error "Route for '$domain' not found in Caddy"; return 1; }

  local resp
  resp="$(curl -sf -o /dev/null -w '%{http_code}' \
    -X DELETE "${routes_url}/${idx}")"
  [[ $resp =~ ^2 ]] || { ui::error "Caddy API error removing route: HTTP $resp"; return 1; }
}

proxy::_api_load_cert() {
  local cert_path="$1" key_path="$2"
  local payload="{\"load_files\":[{\"certificate\":\"${cert_path}\",\"key\":\"${key_path}\"}]}"
  curl -sf -o /dev/null \
    -X POST "${TALC_CADDY_API}/config/apps/tls/certificates" \
    -H 'Content-Type: application/json' \
    -d "$payload" || ui::warn "Could not load TLS cert via Caddy API"
}

# ── Caddyfile fallback ────────────────────────────────────────────────────────

proxy::_file_add_route() {
  local domain="$1" port="$2" ip="$3" cert_path="${4:-}" key_path="${5:-}"
  local routes
  declare -A routes
  proxy::_file_load_routes routes

  routes[$domain]="${ip}:${port}:${cert_path}:${key_path}"
  proxy::_file_save_routes routes
}

proxy::_file_remove_route() {
  local domain="$1"
  local routes
  declare -A routes
  proxy::_file_load_routes routes

  if [[ -z ${routes[$domain]:-} ]]; then
    ui::error "Route for '$domain' not found in Caddyfile"
    return 1
  fi
  unset "routes[$domain]"
  proxy::_file_save_routes routes
}

proxy::_file_load_routes() {
  local -n _routes_ref=$1
  [[ -f $CADDYFILE ]] || return 0
  local content
  content="$(priv::read_file "$CADDYFILE")"
  local section
  section="$(proxy::_extract_talc_section "$content")" || return 0
  [[ -z $section ]] && return 0

  local cur_domain=''
  while IFS= read -r line; do
    line="${line#"${line%%[![:space:]]*}"}"  # ltrim
    if [[ $line =~ ^([a-zA-Z0-9._-]+)(,[[:space:]]*\*\.[a-zA-Z0-9._-]+)?[[:space:]]*\{ ]]; then
      cur_domain="${BASH_REMATCH[1]}"
    elif [[ $line =~ ^reverse_proxy[[:space:]]+([^:]+):([0-9]+) && -n $cur_domain ]]; then
      local rp_ip="${BASH_REMATCH[1]}" rp_port="${BASH_REMATCH[2]}"
      _routes_ref[$cur_domain]="${rp_ip}:${rp_port}::"
    elif [[ $line == '}' ]]; then
      cur_domain=''
    fi
  done <<< "$section"
}

proxy::_file_save_routes() {
  local -n _routes_ref=$1
  local full=''
  [[ -f $CADDYFILE ]] && full="$(priv::read_file "$CADDYFILE")"

  # Strip existing talc section
  local rest; rest="$(proxy::_strip_talc_section "$full")"

  # Build new talc section
  local section
  section="$(proxy::_generate_section _routes_ref)"

  local new_content
  if [[ -z ${rest// /} ]]; then
    new_content="${CADDY_MARKER_START}
${section}
${CADDY_MARKER_END}
"
  else
    new_content="${CADDY_MARKER_START}
${section}
${CADDY_MARKER_END}

${rest}"
  fi
  priv::write_file "$CADDYFILE" "$new_content"
}

proxy::_generate_section() {
  local -n _gen_routes=$1
  local out=''
  # On-demand TLS global block + ask endpoint
  out+=$'{\n  on_demand_tls {\n    ask http://127.0.0.1/talc-ask\n  }\n}\n\n'
  out+=':80 {\n  handle /talc-ask {\n    respond 200\n  }\n}\n\n'
  for domain in "${!_gen_routes[@]}"; do
    local val="${_gen_routes[$domain]}"
    local ip port cert key
    IFS=':' read -r ip port cert key <<< "$val"
    out+="${domain}, *.${domain} {\n"
    out+="  tls {\n    on_demand\n  }\n"
    out+="  reverse_proxy ${ip}:${port}\n"
    out+="}\n\n"
  done
  printf '%s' "$out"
}

proxy::_extract_talc_section() {
  local content="$1"
  [[ $content == *"$CADDY_MARKER_START"* && $content == *"$CADDY_MARKER_END"* ]] || return 1
  local after_start="${content#*"$CADDY_MARKER_START"}"
  printf '%s' "${after_start%%"$CADDY_MARKER_END"*}"
}

proxy::_strip_talc_section() {
  local content="$1"
  [[ $content == *"$CADDY_MARKER_START"* ]] || { printf '%s' "$content"; return 0; }
  local before="${content%%"$CADDY_MARKER_START"*}"
  local after="${content#*"$CADDY_MARKER_END"}"
  local combined="${before}${after}"
  # Trim leading/trailing blank lines
  printf '%s' "${combined}" | sed '/^[[:space:]]*$/d' | sed '1{/^$/d}'
}

proxy::_file_reload_or_warn() {
  command -v caddy &>/dev/null || return 0
  if svc::running caddy; then
    priv::exec systemctl reload caddy 2>/dev/null || \
      ui::warn "Caddy reload failed. Run: sudo systemctl reload caddy"
  else
    priv::exec systemctl start caddy 2>/dev/null || \
      ui::warn "Caddy start failed. Run: sudo systemctl start caddy"
  fi
}
