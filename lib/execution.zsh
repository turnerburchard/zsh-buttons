# preexec doesn't fire from a precmd hook, so log and mark the command here.
_zb_run() {
  print -s -- "$1"
  _zb_log_command "$1"
  print -r -- $'\e[2m❯\e[0m'" $1"
  printf '%s' $'\e]133;C\a'
  eval "$1"
}

# Takes over the display arrays, so the grid that called this must not read them again.
_zb_followup() {
  local head=$1
  local -a fh=() ft=()
  local -i j
  for (( j = 1; j <= ${#_zb_fu_for}; j++ )); do
    [[ ${_zb_fu_for[j]} == "$head" ]] || continue
    fh+=( "${_zb_fu_cmd[j]}" ); ft+=( '' )
  done
  (( ${#fh} )) || return
  _zb_heads=( "${(@)fh}" ); _zb_tails=( "${(@)ft}" )
  _zb_grid 1 0
}

# Runs entry $1, or pushes it onto the prompt when it needs an argument. $2 allows a
# follow-up grid once the command is done.
_zb_activate() {
  local -i i=$1 allow_followup=$2
  local head=${_zb_heads[i]} tail=${_zb_tails[i]}
  local -i started

  if [[ -z $tail ]]; then
    if [[ -n ${_zb_takes_arg[$head]} ]]; then
      print -z -- "$head "
      return
    fi
    started=$EPOCHSECONDS
    _zb_run "$head"
    (( allow_followup && EPOCHSECONDS - started <= 30 )) && _zb_followup "$head"
    return
  fi

  if [[ -n ${_zb_takes_arg[$head]} ]]; then
    _zb_cursor=$(( ${#head} + 1 ))
    print -z -- "$head  && $tail"
  elif [[ -n ${_zb_takes_arg[$tail]} ]]; then
    print -z -- "$head && $tail "
  else
    _zb_run "$head && $tail"
  fi
}
