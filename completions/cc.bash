#!/usr/bin/env bash
# cc-kit bash completion — sourced by init.sh
#
# Provides tab-completion for all cc-* commands. Works with bash 3.2+
# (macOS default) and bash 4+ (Linux).
#
# Customize: set CC_KIT_COMPLETION=0 before sourcing init.sh to disable.
[[ "${CC_KIT_COMPLETION:-1}" != "1" ]] && return 0

# ── cc-switch ────────────────────────────────────────────────────────
# Usage: cc-switch <provider> [model] [--new-key]
_cc_complete_switch() {
  local cur prev words cword
  _get_comp_words_by_ref -n : cur prev words cword 2>/dev/null || {
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"
    cword="${COMP_CWORD}"
  }

  # If we're completing the first argument (provider)
  if [[ $cword -eq 1 ]]; then
    COMPREPLY=($(compgen -W "deepseek minimax glm anthropic show --help -h --new-key" -- "$cur"))
    return 0
  fi

  # Second argument: model variants, depends on provider
  local provider="${COMP_WORDS[1]}"
  case "$provider" in
    deepseek)
      COMPREPLY=($(compgen -W "pro flash --new-key -n" -- "$cur")) ;;
    minimax)
      COMPREPLY=($(compgen -W "m2.7 highspeed m3 --new-key -n" -- "$cur")) ;;
    glm)
      COMPREPLY=($(compgen -W "4.7 5.1 5.2 flash --new-key -n" -- "$cur")) ;;
    anthropic)
      COMPREPLY=($(compgen -W "--new-key -n" -- "$cur")) ;;
  esac
  return 0
}

# ── cc-mode ───────────────────────────────────────────────────────────
_cc_complete_mode() {
  local cur
  _get_comp_words_by_ref -n : cur 2>/dev/null || cur="${COMP_WORDS[COMP_CWORD]}"
  COMPREPLY=($(compgen -W "single wide full show --help -h" -- "$cur"))
  return 0
}

# ── cc-balance ────────────────────────────────────────────────────────
_cc_complete_balance() {
  local cur
  _get_comp_words_by_ref -n : cur 2>/dev/null || cur="${COMP_WORDS[COMP_CWORD]}"
  COMPREPLY=($(compgen -W "deepseek minimax glm auto --help -h" -- "$cur"))
  return 0
}

# ── cc-doctor ─────────────────────────────────────────────────────────
_cc_complete_doctor() {
  local cur
  _get_comp_words_by_ref -n : cur 2>/dev/null || cur="${COMP_WORDS[COMP_CWORD]}"
  COMPREPLY=($(compgen -W "--json --fix --help -h" -- "$cur"))
  return 0
}

# ── cc-status ─────────────────────────────────────────────────────────
_cc_complete_status() {
  local cur
  _get_comp_words_by_ref -n : cur 2>/dev/null || cur="${COMP_WORDS[COMP_CWORD]}"
  COMPREPLY=($(compgen -W "single wide full --help -h" -- "$cur"))
  return 0
}

# ── Register completions ──────────────────────────────────────────────
# complete is a bash builtin; guard with a test so this file can be
# sourced from zsh/bash_profile without errors (zsh has its own system).
if declare -F complete >/dev/null 2>&1; then
  complete -F _cc_complete_switch  cc-switch
  complete -F _cc_complete_mode    cc-mode
  complete -F _cc_complete_balance cc-balance
  complete -F _cc_complete_doctor  cc-doctor
  complete -F _cc_complete_status  cc-status
fi

# Quietly clean up so we don't pollute the namespace more than needed.
# The completion functions must stay exported for complete -F to find them.
