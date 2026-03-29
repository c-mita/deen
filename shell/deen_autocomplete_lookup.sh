#!/usr/bin/bash

_deen_matching_words() {

  local cur
  cur="${COMP_WORDS[COMP_CWORD]}"
  _script_commands=$(deen --walk $cur)
  COMPREPLY=( $(compgen -W "${_script_commands}") )
  return 0
}

complete -F _deen_matching_words deen
