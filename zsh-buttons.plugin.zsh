# zsh-buttons - buttons for the commands you run most: run one, or prefill the prompt with it.
#
# A function rather than a script on PATH: a button can be a shell function or an alias, and
# can cd the caller. A forked child process can do none of that.

zmodload -F zsh/datetime p:EPOCHSECONDS
zmodload -F zsh/stat b:zstat
autoload -Uz add-zsh-hook

# No colon, so ZSH_BUTTONS_CMD= (empty) means bind nothing, rather than falling back to f.
: ${ZSH_BUTTONS_CMD=f}
: ${ZSH_BUTTONS_CONFIG:=${XDG_CONFIG_HOME:-$HOME/.config}/zsh-buttons/config.zsh}
: ${ZSH_BUTTONS_STATE:=${XDG_DATA_HOME:-$HOME/.local/share}/zsh-buttons}
: ${ZSH_BUTTONS_WINDOW_DAYS:=30}
: ${ZSH_BUTTONS_REFRESH_HOURS:=24}
: ${ZSH_BUTTONS_MAX_PER_ROW:=3}
: ${ZSH_BUTTONS_SLOTS:=9}
: ${ZSH_BUTTONS_MODE:=automatic}

typeset -ga _zb_commands=() _zb_pinned=() _zb_ignored=()
typeset -gA _zb_labels=() _zb_takes_arg=()

# What's on screen. _zb_tails[i] is empty unless entry i is a chain, in which case it holds
# the command that runs after _zb_heads[i]. _zb_fu_for/_zb_fu_cmd pair a button with a
# command that habitually follows it.
typeset -ga _zb_heads=() _zb_tails=() _zb_fu_for=() _zb_fu_cmd=()
typeset -ga _zb_box=() _zb_box_dim=()

_zb_validate_command() {
  [[ $1 != *$'\t'* && $1 != *$'\n'* ]] && return
  print -u2 'zsh-buttons: commands cannot contain tabs or newlines'
  return 1
}

buttons_pin() {
  local cmd
  for cmd in "$@"; do _zb_validate_command "$cmd" || return; done
  _zb_pinned+=( "$@" )
}

buttons_ignore() {
  local cmd
  for cmd in "$@"; do _zb_validate_command "$cmd" || return; done
  _zb_ignored+=( "$@" )
}

buttons_add() {
  local cmd=$1
  _zb_validate_command "$cmd" || return
  shift
  _zb_commands+=( "$cmd" )
  while (( $# )); do
    case $1 in
      --arg)   _zb_takes_arg[$cmd]=1; shift ;;
      --label) _zb_labels[$cmd]=$2;   shift 2 ;;
      *) print -u2 "zsh-buttons: unknown option for '$cmd': $1"; return 1 ;;
    esac
  done
}

[[ -r $ZSH_BUTTONS_CONFIG ]] && source $ZSH_BUTTONS_CONFIG
if [[ $ZSH_BUTTONS_MODE != automatic && $ZSH_BUTTONS_MODE != manual ]]; then
  print -u2 "zsh-buttons: ZSH_BUTTONS_MODE must be 'automatic' or 'manual'"
  return 1
fi

source "${${(%):-%x}:A:h}/lib/ranking.zsh" || return
source "${${(%):-%x}:A:h}/lib/ui.zsh" || return
source "${${(%):-%x}:A:h}/lib/execution.zsh" || return

zsh_buttons() {
  emulate -L zsh
  _zb_load_order
  (( ${#_zb_heads} )) || return
  _zb_grid 3 1
}

# Copy this ASCII-only dispatcher, never zsh_buttons itself: $functions[...] hands back
# zsh's metafied text and assigning it back doesn't unmetafy, so non-ASCII gets corrupted.
_zb_dispatch() { zsh_buttons "$@" }
[[ -n $ZSH_BUTTONS_CMD ]] && functions[$ZSH_BUTTONS_CMD]=$functions[_zb_dispatch]

# print -z always drops the cursor at the end of the buffer, so a chain that takes its
# argument in the middle needs ZLE to move it back once the line is loaded.
typeset -gi _zb_cursor=-1
_zb_line_init() {
  if (( _zb_cursor >= 0 )); then
    CURSOR=$_zb_cursor
    _zb_cursor=-1
  fi
  (( ${+widgets[_zb_prev_line_init]} )) && zle _zb_prev_line_init
}
if [[ ${widgets[zle-line-init]} != user:_zb_line_init ]]; then
  (( ${+widgets[zle-line-init]} )) && zle -A zle-line-init _zb_prev_line_init
  zle -N zle-line-init _zb_line_init
fi

add-zsh-hook preexec _zb_log_command

# Show the buttons once, on the first prompt. This hook has to land after any deferred
# shell init, or a button runs before things like a version manager have loaded.
_zb_autostart() {
  add-zsh-hook -d precmd _zb_autostart
  [[ -o interactive && -t 0 ]] || return
  zsh_buttons
}
add-zsh-hook precmd _zb_autostart
