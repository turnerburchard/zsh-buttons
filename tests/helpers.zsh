setopt pipefail
zmodload -F zsh/datetime p:EPOCHSECONDS

typeset -gr TEST_REPO=${${(%):-%x}:A:h:h}

fail() {
  print -u2 -- "FAIL: $1"
  return 1
}

assert_equal() {
  local expected=$1 actual=$2 description=$3
  [[ $actual == "$expected" ]] || fail "$description: expected '$expected', got '$actual'"
}

setup_test() {
  TEST_TMP=$(mktemp -d "${TMPDIR:-/tmp}/zsh-buttons-test.XXXXXX")
  ZSH_BUTTONS_CONFIG=$TEST_TMP/config.zsh
  ZSH_BUTTONS_STATE=$TEST_TMP/state
  mkdir -p "$ZSH_BUTTONS_STATE"
  : > "$ZSH_BUTTONS_CONFIG"
  TEST_TIMESTAMP=$(( EPOCHSECONDS - 1000 ))
}

append_commands() {
  local command=$1 count=$2
  local -i i
  for (( i = 1; i <= count; i++ )); do
    append_command "$command"
  done
}

append_command() {
  local command=$1
  (( TEST_TIMESTAMP++ ))
  print -r -- "$TEST_TIMESTAMP"$'\t'"$TEST_TMP"$'\t'"$command" >> "$ZSH_BUTTONS_STATE/commands.log"
}

write_config() {
  print -r -- "$1" >> "$ZSH_BUTTONS_CONFIG"
}

load_plugin() {
  source "$TEST_REPO/zsh-buttons.plugin.zsh"
}
