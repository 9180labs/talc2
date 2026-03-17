#!/usr/bin/env bash
# network.sh — detect local LAN IP
# shellcheck shell=bash
set -euo pipefail

# Preferred interface order (first match wins)
_NET_PREFERRED=(wlan0 eth0)

# network::detect_local_ip — prints the best LAN IP
network::detect_local_ip() {
  # Gather non-loopback IPv4 addresses with their interface names
  # ip -4 addr show output:
  #   2: eth0    inet 192.168.1.5/24 ...
  declare -A by_iface
  while IFS= read -r line; do
    local iface ip
    if [[ $line =~ ^[[:space:]]+inet[[:space:]]([0-9.]+)/ ]]; then
      ip="${BASH_REMATCH[1]}"
      # Stash under the last seen interface name
      [[ -n ${_last_iface:-} ]] && by_iface[$_last_iface]="$ip"
    elif [[ $line =~ ^[0-9]+:[[:space:]]+([^:@]+) ]]; then
      _last_iface="${BASH_REMATCH[1]// /}"
    fi
  done < <(ip -4 addr show 2>/dev/null)
  unset _last_iface

  # Try preferred interfaces first
  for iface in "${_NET_PREFERRED[@]}"; do
    if [[ -n ${by_iface[$iface]:-} ]] && _is_private_ip "${by_iface[$iface]}"; then
      printf '%s\n' "${by_iface[$iface]}"
      return 0
    fi
  done

  # Fall back to any enp* (common PCI Ethernet naming)
  for iface in "${!by_iface[@]}"; do
    if [[ $iface =~ ^enp ]] && _is_private_ip "${by_iface[$iface]}"; then
      printf '%s\n' "${by_iface[$iface]}"
      return 0
    fi
  done

  # Fall back to any private IP
  for iface in "${!by_iface[@]}"; do
    if _is_private_ip "${by_iface[$iface]}"; then
      printf '%s\n' "${by_iface[$iface]}"
      return 0
    fi
  done

  ui::error "No private LAN IP address found. Are you connected to a network?"
  return 1
}

_is_private_ip() {
  local ip="$1"
  local -a octets
  IFS='.' read -ra octets <<< "$ip"
  (( ${#octets[@]} == 4 )) || return 1
  local a="${octets[0]}" b="${octets[1]}"
  # 10.x.x.x
  (( a == 10 )) && return 0
  # 172.16–31.x.x
  (( a == 172 && b >= 16 && b <= 31 )) && return 0
  # 192.168.x.x
  (( a == 192 && b == 168 )) && return 0
  return 1
}
