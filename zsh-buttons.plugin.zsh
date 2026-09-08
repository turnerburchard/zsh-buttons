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

# Derived after the config is read, so a config that sets ZSH_BUTTONS_STATE still takes effect.
typeset -g _zb_log=$ZSH_BUTTONS_STATE/commands.log
typeset -g _zb_cache=$ZSH_BUTTONS_STATE/cache
typeset -g _zb_cmd=${ZSH_BUTTONS_CMD:-zsh_buttons}
typeset -g _zb_cache_version=2
typeset -g _zb_cache_key=$_zb_cache_version:$ZSH_BUTTONS_MODE:$ZSH_BUTTONS_SLOTS:$ZSH_BUTTONS_WINDOW_DAYS

_zb_stale() {
  [[ -s $_zb_cache ]] || return 0
  local version mode
  IFS=$'\t' read -r version mode < $_zb_cache
  [[ $version == V && $mode == $_zb_cache_key ]] || return 0
  [[ $ZSH_BUTTONS_CONFIG -nt $_zb_cache ]] && return 0
  if [[ $ZSH_BUTTONS_MODE == automatic && $_zb_log -nt $_zb_cache ]]; then
    local kind head tail
    local -i buttons=0
    while IFS=$'\t' read -r kind head tail; do
      [[ $kind == B ]] && (( buttons++ ))
    done < $_zb_cache
    (( buttons < ZSH_BUTTONS_SLOTS )) && return 0
  fi
  local -a st
  zstat -A st +mtime $_zb_cache
  (( EPOCHSECONDS - st[1] >= ZSH_BUTTONS_REFRESH_HOURS * 3600 ))
}

# Counts each button's uses inside the window, plus every ordered pair of buttons that ran
# back to back, then writes the ranked display list and the follow-up map. One awk fork, and
# only when the cache has expired. With no log it falls through to the config order, since
# every count stays zero.
_zb_rank_manual() {
  local -a logfile=()
  [[ -s $_zb_log ]] && logfile=( $_zb_log )
  local cmd mode pin
  for cmd in $_zb_commands; do
    mode=E
    [[ -n ${_zb_takes_arg[$cmd]} ]] && mode=P
    pin=${_zb_pinned[(i)$cmd]}
    (( pin > ${#_zb_pinned} )) && pin=0
    print -r -- "$mode"$'\t'"$pin"$'\t'"$cmd"
  done | awk -F'\t' -v slots=$ZSH_BUTTONS_SLOTS \
      -v cutoff=$(( EPOCHSECONDS - ZSH_BUTTONS_WINDOW_DAYS * 86400 )) '
    BEGIN { gap = 10; mincount = 3; chain_conf = 0.6; fu_conf = 0.3; fu_max = 3 }

    # Every ordered pair of buttons is a chain the log might contain. Building them up front
    # keeps resolution to a single pass, so a chain you press feeds its own rank.
    function build(   i, j) {
      for (i = 1; i <= n; i++)
        for (j = 1; j <= n; j++) {
          if (i == j || (mode[i] == "P" && mode[j] == "P")) continue
          m++
          ca[m] = i; cb[m] = j
          clen[m] = length(cmd[i]) + 4 + length(cmd[j])
          if (mode[i] == "P")      { cpre[m] = cmd[i] " ";               csuf[m] = " && " cmd[j] }
          else if (mode[j] == "P") { cpre[m] = cmd[i] " && " cmd[j] " "; csuf[m] = "" }
          else                     { cpre[m] = cmd[i] " && " cmd[j];     csuf[m] = ""; cfix[m] = 1 }
        }
    }

    function chain_matches(k, s) {
      if (cfix[k]) return s == cpre[k]
      if (length(s) <= length(cpre[k]) + length(csuf[k])) return 0
      if (index(s, cpre[k]) != 1) return 0
      return csuf[k] == "" || substr(s, length(s) - length(csuf[k]) + 1) == csuf[k]
    }

    function ranks_before(a, b,   pa, pb) {
      pa = (epin[a] ? 0 : 1); pb = (epin[b] ? 0 : 1)
      if (pa != pb) return pa < pb
      if (epin[a]) return epin[a] < epin[b]
      if (ecnt[a] != ecnt[b]) return ecnt[a] > ecnt[b]
      return eord[a] < eord[b]
    }

    NR == FNR { n++; mode[n] = $1; pin[n] = $2 + 0; cmd[n] = $3; next }

    !built { build(); built = 1 }

    {
      if (NF != 3) { prev = ""; next }
      ts = $1 + 0
      line = $0
      sub(/^[^\t]*\t[^\t]*\t/, "", line)
      if (ts < cutoff) { prev = 0; next }

      # Longest match only. A prefix button like "git checkout" would otherwise also swallow
      # every use of a more specific one like "git checkout main" and count it twice.
      best = 0; bestlen = -1; chained = 0
      for (i = 1; i <= n; i++)
        if (line == cmd[i] || (mode[i] == "P" && index(line, cmd[i] " ") == 1))
          if (length(cmd[i]) > bestlen) { bestlen = length(cmd[i]); best = i; chained = 0 }
      for (k = 1; k <= m; k++)
        if (chain_matches(k, line) && clen[k] > bestlen) { bestlen = clen[k]; best = k; chained = 1 }

      if (!best) { prev = 0; next }
      if (chained) {
        # Pressing a chain is running both halves, so it feeds the counters the raw pair would.
        uses[ca[best]]++
        succ[ca[best] SUBSEP cb[best]]++
        # Only a command start is logged, so a chain cannot anchor whatever follows it.
        prev = 0
        next
      }
      uses[best]++
      solo[best]++
      if (prev && ts - pts <= gap) succ[prev SUBSEP best]++
      prev = best; pts = ts
    }

    END {
      for (i = 1; i <= n; i++) {
        e++; ekind[e] = "B"; eref[e] = i; ecnt[e] = solo[i] + 0; epin[e] = pin[i]; eord[e] = i
      }
      for (k = 1; k <= m; k++) {
        s = succ[ca[k] SUBSEP cb[k]] + 0
        if (s < mincount || s < chain_conf * uses[ca[k]]) continue
        e++; ekind[e] = "C"; eref[e] = k; ecnt[e] = s; epin[e] = 0; eord[e] = n + k
      }

      for (x = 1; x <= e; x++) ord[x] = x
      for (x = 1; x <= e; x++) {
        b = x
        for (y = x + 1; y <= e; y++) if (ranks_before(ord[y], ord[b])) b = y
        t = ord[x]; ord[x] = ord[b]; ord[b] = t
      }

      for (x = 1; x <= e && x <= slots; x++) {
        p = ord[x]
        if (ekind[p] == "B") { print "B\t" cmd[eref[p]] "\t"; continue }
        k = eref[p]
        print "C\t" cmd[ca[k]] "\t" cmd[cb[k]]
        chained_pair[ca[k] SUBSEP cb[k]] = 1
      }

      # A successor only earns a follow-up if it survived the grid cut as nothing else, since
      # a chain on screen already offers it.
      for (i = 1; i <= n; i++) {
        if (mode[i] == "P") continue
        f = 0
        for (j = 1; j <= n; j++) {
          if (i == j || chained_pair[i SUBSEP j]) continue
          s = succ[i SUBSEP j] + 0
          if (s < mincount || s < fu_conf * uses[i]) continue
          f++; fj[f] = j; fs[f] = s
        }
        for (x = 1; x <= f && x <= fu_max; x++) {
          b = x
          for (y = x + 1; y <= f; y++) if (fs[y] > fs[b]) b = y
          t = fj[x]; fj[x] = fj[b]; fj[b] = t
          t = fs[x]; fs[x] = fs[b]; fs[b] = t
          print "F\t" cmd[i] "\t" cmd[fj[x]]
        }
      }
    }
  ' /dev/stdin $logfile
}

_zb_rank_automatic() {
  local -a logfile=()
  [[ -s $_zb_log ]] && logfile=( $_zb_log )
  local cmd pin
  {
    print -r -- $'M\t0\t'
    for cmd in $_zb_pinned; do
      pin=${_zb_pinned[(i)$cmd]}
      print -r -- $'P\t'"$pin"$'\t'"$cmd"
    done
    for cmd in $_zb_ignored; do
      print -r -- $'I\t0\t'"$cmd"
    done
  } | awk -F'\t' -v slots=$ZSH_BUTTONS_SLOTS \
      -v cutoff=$(( EPOCHSECONDS - ZSH_BUTTONS_WINDOW_DAYS * 86400 )) '
    BEGIN { gap = 10; mincount = 3; fu_conf = 0.3; fu_max = 3 }

    function ranks_before(a, b,   ca, cb) {
      ca = entry[a]; cb = entry[b]
      if (pinned[ca] || pinned[cb]) {
        if (!pinned[ca]) return 0
        if (!pinned[cb]) return 1
        return pinned[ca] < pinned[cb]
      }
      if (uses[ca] != uses[cb]) return uses[ca] > uses[cb]
      if (last[ca] != last[cb]) return last[ca] > last[cb]
      return ca < cb
    }

    NR == FNR {
      if ($1 == "P" && !pinned[$3]) pinned[$3] = $2 + 0
      if ($1 == "I") ignored[$3] = 1
      next
    }

    {
      if (NF != 3) { prev = ""; next }
      ts = $1 + 0
      line = $0
      sub(/^[^\t]*\t[^\t]*\t/, "", line)
      if (ts < cutoff || ignored[line]) { prev = ""; next }

      uses[line]++
      if (ts > last[line]) last[line] = ts
      if (prev != "" && ts - pts <= gap) succ[prev SUBSEP line]++
      prev = line; pts = ts
    }

    END {
      for (cmd in pinned) if (!ignored[cmd]) uses[cmd] += 0
      for (cmd in uses) {
        if (ignored[cmd]) continue
        count++
        entry[count] = cmd
      }

      selected_count = count < slots ? count : slots
      for (x = 1; x <= selected_count; x++) {
        best = 0
        for (y = 1; y <= count; y++)
          if (!chosen[y] && (!best || ranks_before(y, best))) best = y
        chosen[best] = 1
        selected[x] = entry[best]
        print "B\t" selected[x] "\t"
      }

      for (x = 1; x <= selected_count; x++) {
        head = selected[x]
        followup_count = 0
        for (y = 1; y <= selected_count; y++) {
          tail = selected[y]
          if (head == tail) continue
          occurrences = succ[head SUBSEP tail] + 0
          if (occurrences < mincount || occurrences < fu_conf * uses[head]) continue
          followup_count++
          followup[followup_count] = tail
          followup_uses[followup_count] = occurrences
        }
        for (y = 1; y <= followup_count && y <= fu_max; y++) {
          best = y
          for (z = y + 1; z <= followup_count; z++)
            if (followup_uses[z] > followup_uses[best] ||
                (followup_uses[z] == followup_uses[best] && followup[z] < followup[best])) best = z
          swap = followup[y]; followup[y] = followup[best]; followup[best] = swap
          swap = followup_uses[y]; followup_uses[y] = followup_uses[best]; followup_uses[best] = swap
          print "F\t" head "\t" followup[y]
        }
      }
    }
  ' /dev/stdin $logfile
}

_zb_rank() {
  print -r -- $'V\t'"$_zb_cache_key"
  if [[ $ZSH_BUTTONS_MODE == manual ]]; then
    _zb_rank_manual
  else
    _zb_rank_automatic
  fi
}

_zb_load_order() {
  [[ $ZSH_BUTTONS_MODE != manual || ${#_zb_commands} -gt 0 ]] || return
  [[ -d $ZSH_BUTTONS_STATE ]] || mkdir -p $ZSH_BUTTONS_STATE
  _zb_stale && _zb_rank > $_zb_cache

  _zb_heads=() _zb_tails=() _zb_fu_for=() _zb_fu_cmd=()
  local kind head tail
  local -a plain=()
  while IFS=$'\t' read -r kind head tail; do
    [[ $kind == V ]] && continue
    if [[ $ZSH_BUTTONS_MODE == manual ]]; then
      (( ${_zb_commands[(I)$head]} )) || continue
      [[ -n $tail ]] && { (( ${_zb_commands[(I)$tail]} )) || continue }
    fi
    case $kind in
      B) plain+=( "$head" ) ;&
      C) _zb_heads+=( "$head" ); _zb_tails+=( "$tail" ) ;;
      F) _zb_fu_for+=( "$head" ); _zb_fu_cmd+=( "$tail" ) ;;
    esac
  done < $_zb_cache

  if [[ $ZSH_BUTTONS_MODE == manual ]]; then
    local cmd
    for cmd in $_zb_commands; do
      (( ${plain[(I)$cmd]} )) && continue
      _zb_heads+=( "$cmd" ); _zb_tails+=( '' )
    done
  fi

  if (( ${#_zb_heads} > ZSH_BUTTONS_SLOTS )); then
    _zb_heads=( "${(@)_zb_heads[1,ZSH_BUTTONS_SLOTS]}" )
    _zb_tails=( "${(@)_zb_tails[1,ZSH_BUTTONS_SLOTS]}" )
  fi
}

# Sets REPLY rather than printing: $(...) would fork a subshell per cell, per keypress.
_zb_cell() {
  local text=$1 width=$2 pad
  (( ${#text} > width )) && text=${text[1,width]}
  pad=$(( (width - ${#text}) / 2 ))
  printf -v REPLY '%*s%s%*s' $pad '' "$text" $(( width - pad - ${#text} )) ''
}

# Fills _zb_box with entry $1's content rows, and _zb_box_dim with a colour override per row.
_zb_box_rows() {
  local -i i=$1 rows=$2
  local head=${_zb_heads[i]} tail=${_zb_tails[i]} htext ttext
  htext=${_zb_labels[$head]:-$head}
  [[ -n ${_zb_takes_arg[$head]} ]] && htext+=' <input>'
  if (( rows == 1 )); then
    _zb_box=( "$htext" ); _zb_box_dim=( '' )
  elif [[ -z $tail ]]; then
    _zb_box=( '' "$htext" '' ); _zb_box_dim=( '' '' '' )
  else
    ttext=${_zb_labels[$tail]:-$tail}
    [[ -n ${_zb_takes_arg[$tail]} ]] && ttext+=' <input>'
    _zb_box=( "$htext" '&&' "$ttext" ); _zb_box_dim=( '' $'\e[2m' '' )
  fi
}

_zb_render() {
  local -i sel=$1 per_row=$2 width=$3 gap=$4 rows=$5
  local footer=$6
  local -i inner=$(( width - 2 )) n=${#_zb_heads} i start r
  local reset=$'\e[0m' dim=$'\e[2m'
  local bar='' spacer='' border name tl tr bl br REPLY
  local -a out
  repeat $inner bar+='─'
  repeat $gap spacer+=' '

  for (( start = 1; start <= n; start += per_row )); do
    out=()
    for (( r = 1; r <= rows + 2; r++ )) out+=( '' )
    for (( i = start; i < start + per_row && i <= n; i++ )); do
      if (( i == sel )); then
        border=$'\e[36m' name=$'\e[1;36m' tl='╭' tr='╮' bl='╰' br='╯'
      else
        border=$dim name='' tl='┌' tr='┐' bl='└' br='┘'
      fi
      if (( i > start )); then
        for (( r = 1; r <= rows + 2; r++ )) out[r]+=$spacer
      fi
      out[1]+="${border}${tl}${bar}${tr}${reset}"
      _zb_box_rows $i $rows
      for (( r = 1; r <= rows; r++ )); do
        _zb_cell "${_zb_box[r]}" $inner
        out[r+1]+="${border}│${reset}${_zb_box_dim[r]:-$name}${REPLY}${reset}${border}│${reset}"
      done
      out[rows+2]+="${border}${bl}${bar}${br}${reset}"
    done
    for (( r = 1; r <= rows + 2; r++ )) print -r -- "  ${out[r]}"
  done
  print -r -- "  ${dim}${footer}${reset}"
}

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

_zb_grid() {
  local -i rows=$1 allow_followup=$2
  local -i n=${#_zb_heads}
  local -i width=24 gap=2
  local -i cap=$(( (COLUMNS - 2 + gap) / (width + gap) ))
  (( cap < 1 )) && cap=1
  local -i per_row=$(( cap < ZSH_BUTTONS_MAX_PER_ROW ? cap : ZSH_BUTTONS_MAX_PER_ROW ))
  local -i grid_rows=$(( (n + per_row - 1) / per_row ))
  # Rebalance so the rows come out even instead of leaving a stub row.
  per_row=$(( (n + grid_rows - 1) / grid_rows ))
  local -i height=$(( grid_rows * (rows + 2) + 1 ))
  local -i sel=1 drawn=0
  local key footer erase=$'\e[%dA\e[J' show=$'\e[?25h'
  # Ghostty decides whether a process is running by whether the cursor sits in an
  # OSC 133 input region, and a precmd hook runs before any prompt is marked.
  local at_prompt=$'\e]133;D\a\e]133;P;k=i\a\e]133;B\a'

  if (( allow_followup )); then
    footer="←→ ↑↓ tab  ·  ⏎ run  ·  1-$(( n > 9 ? 9 : n )) jump  ·  type to dismiss"
  else
    footer="←→ ⏎ run  ·  type to dismiss"
  fi

  trap 'printf "$erase$show" $height; return 130' INT
  printf '\e[?25l'

  while true; do
    (( drawn )) && printf "$erase" $height
    _zb_render $sel $per_row $width $gap $rows "$footer"
    printf '%s' "$at_prompt"
    drawn=1

    read -s -k 1 key || break
    case $key in
      $'\n'|$'\r')
        printf "$erase$show" $height
        _zb_activate $sel $allow_followup
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

_zb_log_command() {
  [[ -z $1 || $1 == [[:space:]]* || $1 == *$'\t'* || $1 == *$'\n'* || $1 == "$_zb_cmd" || $1 == "$_zb_cmd "* ]] && return
  [[ -d $ZSH_BUTTONS_STATE ]] || mkdir -p $ZSH_BUTTONS_STATE
  print -r -- "${EPOCHSECONDS}"$'\t'"${PWD}"$'\t'"$1" >>| $_zb_log
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
