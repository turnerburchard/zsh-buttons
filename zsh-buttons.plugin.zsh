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
: ${ZSH_BUTTONS_MAX_PER_ROW:=4}

typeset -ga _zb_commands=() _zb_pinned=() _zb_display=()
typeset -gA _zb_labels=() _zb_arg_hints=()

buttons_pin() { _zb_pinned+=( "$@" ) }

buttons_add() {
  local cmd=$1
  shift
  _zb_commands+=( "$cmd" )
  while (( $# )); do
    case $1 in
      --arg)   _zb_arg_hints[$cmd]=$2; shift 2 ;;
      --label) _zb_labels[$cmd]=$2;    shift 2 ;;
      *) print -u2 "zsh-buttons: unknown option for '$cmd': $1"; return 1 ;;
    esac
  done
}

[[ -r $ZSH_BUTTONS_CONFIG ]] && source $ZSH_BUTTONS_CONFIG

# Derived after the config is read, so a config that sets ZSH_BUTTONS_STATE still takes effect.
typeset -g _zb_log=$ZSH_BUTTONS_STATE/commands.log
typeset -g _zb_cache=$ZSH_BUTTONS_STATE/order
typeset -g _zb_cmd=${ZSH_BUTTONS_CMD:-zsh_buttons}

_zb_stale() {
  [[ -s $_zb_cache ]] || return 0
  [[ $ZSH_BUTTONS_CONFIG -nt $_zb_cache ]] && return 0
  local -a st
  zstat -A st +mtime $_zb_cache
  (( EPOCHSECONDS - st[1] >= ZSH_BUTTONS_REFRESH_HOURS * 3600 ))
}

# Counts each button's uses inside the window, then orders pinned first, rest by count.
# One awk fork, and only when the cache has expired. With no log it falls through to
# the config order, since every count stays zero.
_zb_rank() {
  local -a logfile=()
  [[ -s $_zb_log ]] && logfile=( $_zb_log )
  local cmd mode pin
  for cmd in $_zb_commands; do
    mode=E
    [[ -n ${_zb_arg_hints[$cmd]} ]] && mode=P
    pin=${_zb_pinned[(i)$cmd]}
    (( pin > ${#_zb_pinned} )) && pin=0
    print -r -- "$mode"$'\t'"$pin"$'\t'"$cmd"
  done | awk -F'\t' -v cutoff=$(( EPOCHSECONDS - ZSH_BUTTONS_WINDOW_DAYS * 86400 )) '
    function ranks_before(a, b,   pa, pb) {
      pa = (pin[a] ? 0 : 1); pb = (pin[b] ? 0 : 1)
      if (pa != pb) return pa < pb
      if (pin[a]) return pin[a] < pin[b]
      if (cnt[a] + 0 != cnt[b] + 0) return cnt[a] + 0 > cnt[b] + 0
      return a < b
    }
    NR == FNR { n++; mode[n] = $1; pin[n] = $2 + 0; cmd[n] = $3; next }
    $1 + 0 < cutoff { next }
    {
      line = $0
      sub(/^[^\t]*\t[^\t]*\t/, "", line)
      # Longest match only. A prefix button like "git checkout" would otherwise also swallow
      # every use of a more specific one like "git checkout main" and count it twice.
      best = 0; bestlen = -1
      for (i = 1; i <= n; i++)
        if (line == cmd[i] || (mode[i] == "P" && index(line, cmd[i] " ") == 1))
          if (length(cmd[i]) > bestlen) { bestlen = length(cmd[i]); best = i }
      if (best) cnt[best]++
    }
    END {
      for (i = 1; i <= n; i++) ord[i] = i
      for (i = 1; i <= n; i++) {
        best = i
        for (j = i + 1; j <= n; j++) if (ranks_before(ord[j], ord[best])) best = j
        t = ord[i]; ord[i] = ord[best]; ord[best] = t
      }
      for (i = 1; i <= n; i++) print cmd[ord[i]]
    }
  ' /dev/stdin $logfile
}

_zb_load_order() {
  (( ${#_zb_commands} )) || return
  [[ -d $ZSH_BUTTONS_STATE ]] || mkdir -p $ZSH_BUTTONS_STATE
  _zb_stale && _zb_rank > $_zb_cache
  _zb_display=( ${(f)"$(<$_zb_cache)"} )
  # Reconcile against the config so an edit can neither drop a button nor keep a stale one.
  _zb_display=( ${(@)_zb_display:*_zb_commands} ${(@)_zb_commands:|_zb_display} )
}

# Sets REPLY rather than printing: $(...) would fork a subshell per cell, per keypress.
_zb_cell() {
  local text=$1 width=$2 pad
  (( ${#text} > width )) && text=${text[1,width]}
  pad=$(( (width - ${#text}) / 2 ))
  printf -v REPLY '%*s%s%*s' $pad '' "$text" $(( width - pad - ${#text} )) ''
}

_zb_render() {
  local sel=$1 per_row=$2 width=$3 gap=$4
  local inner=$(( width - 2 ))
  local reset=$'\e[0m' dim=$'\e[2m'
  local n=${#_zb_display} bar='' spacer='' i start cmd label hint border name tl tr bl br
  local top mid sub bot REPLY
  repeat $inner bar+='─'
  repeat $gap spacer+=' '

  for (( start = 1; start <= n; start += per_row )); do
    top='' mid='' sub='' bot=''
    for (( i = start; i < start + per_row && i <= n; i++ )); do
      cmd=${_zb_display[i]}
      label=${_zb_labels[$cmd]:-$cmd}
      hint=${_zb_arg_hints[$cmd]}
      if (( i == sel )); then
        border=$'\e[36m' name=$'\e[1;36m' tl='╭' tr='╮' bl='╰' br='╯'
      else
        border=$dim name='' tl='┌' tr='┐' bl='└' br='┘'
      fi
      (( i > start )) && { top+=$spacer; mid+=$spacer; sub+=$spacer; bot+=$spacer }
      top+="${border}${tl}${bar}${tr}${reset}"
      _zb_cell "$label" $inner
      mid+="${border}│${reset}${name}${REPLY}${reset}${border}│${reset}"
      _zb_cell "$hint" $inner
      sub+="${border}│${reset}${dim}${REPLY}${reset}${border}│${reset}"
      bot+="${border}${bl}${bar}${br}${reset}"
    done
    print -r -- "  $top"
    print -r -- "  $mid"
    print -r -- "  $sub"
    print -r -- "  $bot"
  done
  print -r -- "  ${dim}←→ ↑↓ tab  ·  ⏎ run  ·  1-$(( n > 9 ? 9 : n )) jump  ·  type to dismiss${reset}"
}

zsh_buttons() {
  emulate -L zsh
  _zb_load_order
  local n=${#_zb_display}
  (( n )) || return

  local -i width=18 gap=2
  local -i cap=$(( (COLUMNS - 2 + gap) / (width + gap) ))
  (( cap < 1 )) && cap=1
  local -i per_row=$(( cap < ZSH_BUTTONS_MAX_PER_ROW ? cap : ZSH_BUTTONS_MAX_PER_ROW ))
  local -i rows=$(( (n + per_row - 1) / per_row ))
  # Rebalance so the rows come out even instead of leaving a stub row.
  per_row=$(( (n + rows - 1) / rows ))
  local -i height=$(( rows * 4 + 1 ))
  local -i sel=1 drawn=0
  local key cmd erase=$'\e[%dA\e[J' show=$'\e[?25h'
  # Ghostty decides whether a process is running by whether the cursor sits in an
  # OSC 133 input region, and a precmd hook runs before any prompt is marked.
  local at_prompt=$'\e]133;D\a\e]133;P;k=i\a\e]133;B\a' running=$'\e]133;C\a'

  trap 'printf "$erase$show" $height; return 130' INT
  printf '\e[?25l'

  while true; do
    (( drawn )) && printf "$erase" $height
    _zb_render $sel $per_row $width $gap
    printf '%s' "$at_prompt"
    drawn=1

    read -s -k 1 key || break
    case $key in
      $'\n'|$'\r')
        cmd=${_zb_display[sel]}
        printf "$erase$show" $height
        if [[ -n ${_zb_arg_hints[$cmd]} ]]; then
          print -z -- "$cmd "
        else
          print -s -- "$cmd"
          # preexec doesn't fire from a precmd hook, so log and mark it here.
          _zb_log_command "$cmd"
          print -r -- $'\e[2m❯\e[0m'" $cmd"
          printf '%s' "$running"
          eval "$cmd"
        fi
        return
        ;;
      $'\t') (( sel = sel % n + 1 )) ;;
      $'\e')
        # Arrows arrive as three bytes, so a bare escape is the read that times out.
        if read -s -t 0.05 -k 1 key && [[ $key == ('['|'O') ]] && read -s -t 0.05 -k 1 key; then
          case $key in
            C) (( sel = sel % n + 1 )) ;;
            D|Z) (( sel = (sel + n - 2) % n + 1 )) ;;
            B) (( sel + per_row <= n )) && (( sel += per_row )) ;;
            A) (( sel - per_row >= 1 )) && (( sel -= per_row )) ;;
          esac
        else
          break
        fi
        ;;
      [1-9]) (( key <= n )) && sel=$key ;;
      $'\x03'|$'\x04') break ;;
      [[:print:]])
        # Whatever was typed behind this key is still queued on the tty, so ZLE reads
        # the rest in order and a fast-typed line arrives intact.
        printf "$erase$show" $height
        print -z -- "$key"
        return
        ;;
    esac
  done

  printf "$erase$show" $height
}

# Copy this ASCII-only dispatcher, never zsh_buttons itself: $functions[...] hands back
# zsh's metafied text and assigning it back doesn't unmetafy, so non-ASCII gets corrupted.
_zb_dispatch() { zsh_buttons "$@" }
[[ -n $ZSH_BUTTONS_CMD ]] && functions[$ZSH_BUTTONS_CMD]=$functions[_zb_dispatch]

_zb_log_command() {
  [[ -z $1 || $1 == [[:space:]]* || $1 == "$_zb_cmd" || $1 == "$_zb_cmd "* ]] && return
  [[ -d $ZSH_BUTTONS_STATE ]] || mkdir -p $ZSH_BUTTONS_STATE
  print -r -- "${EPOCHSECONDS}"$'\t'"${PWD}"$'\t'"${1//$'\n'/ }" >>| $_zb_log
}
add-zsh-hook preexec _zb_log_command

# Show the buttons once, on the first prompt. This hook has to land after any deferred
# shell init, or a button runs before things like a version manager have loaded.
_zb_autostart() {
  add-zsh-hook -d precmd _zb_autostart
  [[ -o interactive && -t 0 ]] || return
  zsh_buttons
}
add-zsh-hook precmd _zb_autostart
