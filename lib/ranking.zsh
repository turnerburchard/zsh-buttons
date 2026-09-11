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

_zb_log_command() {
  [[ -z $1 || $1 == [[:space:]]* || $1 == *$'\t'* || $1 == *$'\n'* || $1 == "$_zb_cmd" || $1 == "$_zb_cmd "* ]] && return
  [[ -d $ZSH_BUTTONS_STATE ]] || mkdir -p $ZSH_BUTTONS_STATE
  print -r -- "${EPOCHSECONDS}"$'\t'"${PWD}"$'\t'"$1" >>| $_zb_log
}
