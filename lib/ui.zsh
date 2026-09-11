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
    footer="←→ ↑↓ tab  ·  ⏎ run  ·  1-$(( n > 9 ? 9 : n )) run  ·  type to dismiss"
  else
    footer="←→ ⏎ run  ·  1-$(( n > 9 ? 9 : n )) run  ·  type to dismiss"
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
      [1-9])
        if (( key <= n )); then
          printf "$erase$show" $height
          _zb_activate $key $allow_followup
          return
        fi
        ;;
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

