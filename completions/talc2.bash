#!/usr/bin/env bash
# talc2 bash completion
# Source this file or place it in /etc/bash_completion.d/talc2
# shellcheck shell=bash

_talc2_domains() {
  local domains_file="${XDG_CONFIG_HOME:-$HOME/.config}/talc2/domains.tsv"
  [[ -f $domains_file ]] || return
  awk -F'\t' '{print $1}' "$domains_file"
}

_talc2_complete() {
  local cur prev words cword
  _init_completion || return

  local commands='setup add remove list update status teardown version help'

  case "$cword" in
    1)
      COMPREPLY=( $(compgen -W "$commands" -- "$cur") )
      return
      ;;
  esac

  local cmd="${words[1]}"
  case "$cmd" in
    remove|rm|update)
      if [[ $cword == 2 ]]; then
        COMPREPLY=( $(compgen -W "$(_talc2_domains)" -- "$cur") )
      fi
      ;;
    list|ls)
      case "$prev" in
        --format|-f)
          COMPREPLY=( $(compgen -W "table json plain" -- "$cur") )
          ;;
        *)
          COMPREPLY=( $(compgen -W "--format" -- "$cur") )
          ;;
      esac
      ;;
    add)
      case "$prev" in
        --port|-p|--ip|-i) ;;
        *)
          COMPREPLY=( $(compgen -W "--port --ip" -- "$cur") )
          ;;
      esac
      ;;
    teardown)
      COMPREPLY=( $(compgen -W "--confirm" -- "$cur") )
      ;;
  esac
}

complete -F _talc2_complete talc
