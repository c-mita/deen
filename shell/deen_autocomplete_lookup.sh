#!/usr/bin/bash

_deen_matching_words() {
  local cur
  cur="${COMP_WORDS[COMP_CWORD]}"
  cur="${cur//\\/}"
  compopt -o filenames -o nospace
  mapfile -t COMPREPLY < <(deen --walk "$cur")
  return 0
}

complete -F _deen_matching_words deen
