#!/usr/bin/env zsh

source "${0:A:h}/helpers.zsh"

test_automatic_mode_ranks_logged_commands() (
  setup_test
  trap 'rm -rf -- "$TEST_TMP"' EXIT
  ZSH_BUTTONS_SLOTS=3
  append_commands claude 5
  append_commands codex 4
  append_commands 'git status' 3

  load_plugin
  _zb_load_order

  assert_equal 3 "${#_zb_heads}" 'automatic button count' || return
  assert_equal claude "${_zb_heads[1]}" 'first automatic button' || return
  assert_equal codex "${_zb_heads[2]}" 'second automatic button' || return
  assert_equal 'git status' "${_zb_heads[3]}" 'third automatic button' || return
)

test_automatic_mode_uses_recency_to_break_ties() (
  setup_test
  trap 'rm -rf -- "$TEST_TMP"' EXIT
  ZSH_BUTTONS_SLOTS=2
  append_commands older 3
  append_commands newer 3

  load_plugin
  _zb_load_order

  assert_equal newer "${_zb_heads[1]}" 'recent tied command' || return
  assert_equal older "${_zb_heads[2]}" 'older tied command' || return
)

test_automatic_mode_applies_ignores_and_pins() (
  setup_test
  trap 'rm -rf -- "$TEST_TMP"' EXIT
  ZSH_BUTTONS_SLOTS=3
  write_config "buttons_ignore 'git pull'"
  write_config 'buttons_pin status'
  append_commands 'git pull' 10
  append_commands claude 5
  append_commands codex 4

  load_plugin
  _zb_load_order

  assert_equal 3 "${#_zb_heads}" 'filtered button count' || return
  assert_equal status "${_zb_heads[1]}" 'unseen pinned command' || return
  assert_equal claude "${_zb_heads[2]}" 'highest ranked command after pin' || return
  assert_equal codex "${_zb_heads[3]}" 'second ranked command after pin' || return
)

test_automatic_mode_learns_followups_without_adding_chains() (
  setup_test
  trap 'rm -rf -- "$TEST_TMP"' EXIT
  ZSH_BUTTONS_SLOTS=2
  append_command setup
  append_command work
  append_command setup
  append_command work
  append_command setup
  append_command work

  load_plugin
  _zb_load_order

  assert_equal 2 "${#_zb_heads}" 'automatic buttons exclude chains' || return
  assert_equal setup "${_zb_fu_for[1]}" 'follow-up source' || return
  assert_equal work "${_zb_fu_cmd[1]}" 'follow-up command' || return
)

test_manual_mode_uses_only_configured_candidates() (
  setup_test
  trap 'rm -rf -- "$TEST_TMP"' EXIT
  ZSH_BUTTONS_SLOTS=2
  write_config 'ZSH_BUTTONS_MODE=manual'
  write_config 'buttons_add deploy'
  write_config 'buttons_add status'
  append_commands ignored 20
  append_commands status 3

  load_plugin
  _zb_load_order

  assert_equal status "${_zb_heads[1]}" 'ranked manual command' || return
  assert_equal deploy "${_zb_heads[2]}" 'unused manual fallback' || return
)

test_manual_mode_keeps_chain_buttons() (
  setup_test
  trap 'rm -rf -- "$TEST_TMP"' EXIT
  ZSH_BUTTONS_SLOTS=3
  write_config 'ZSH_BUTTONS_MODE=manual'
  write_config 'buttons_add setup'
  write_config 'buttons_add work'
  append_commands 'setup && work' 4

  load_plugin
  _zb_load_order

  assert_equal setup "${_zb_heads[1]}" 'manual chain head' || return
  assert_equal work "${_zb_tails[1]}" 'manual chain tail' || return
)

test_cache_version_forces_automatic_refresh() (
  setup_test
  trap 'rm -rf -- "$TEST_TMP"' EXIT
  ZSH_BUTTONS_SLOTS=1
  print -r -- $'B\tstale\t' > "$ZSH_BUTTONS_STATE/cache"
  append_command current

  load_plugin
  _zb_load_order

  assert_equal current "${_zb_heads[1]}" 'button from refreshed cache' || return
)

test_invalid_mode_fails_during_setup() (
  setup_test
  trap 'rm -rf -- "$TEST_TMP"' EXIT
  write_config 'ZSH_BUTTONS_MODE=other'

  if load_plugin 2>/dev/null; then
    fail 'invalid mode loaded successfully'
  fi
)

test_leading_space_keeps_a_command_out_of_the_log() (
  setup_test
  trap 'rm -rf -- "$TEST_TMP"' EXIT

  load_plugin
  _zb_log_command ' secret command'

  [[ ! -e $ZSH_BUTTONS_STATE/commands.log ]] || fail 'leading-space command was logged'
)

test_multiline_command_stays_out_of_automatic_ranking() (
  setup_test
  trap 'rm -rf -- "$TEST_TMP"' EXIT

  load_plugin
  _zb_log_command $'echo first\necho second'
  _zb_load_order

  assert_equal 0 "${#_zb_heads}" 'multiline command button count' || return
)

test_tabbed_command_stays_out_of_automatic_ranking() (
  setup_test
  trap 'rm -rf -- "$TEST_TMP"' EXIT

  load_plugin
  _zb_log_command $'printf first\tsecond'
  buttons_pin $'pinned\tcommand' 2>/dev/null
  _zb_load_order

  assert_equal 0 "${#_zb_heads}" 'tabbed command button count' || return
)

test_underfilled_cache_adds_new_commands_before_daily_refresh() (
  setup_test
  trap 'rm -rf -- "$TEST_TMP"' EXIT
  ZSH_BUTTONS_SLOTS=2
  ZSH_BUTTONS_REFRESH_HOURS=999999
  append_command first

  load_plugin
  _zb_load_order
  touch -t 201901010000 "$ZSH_BUTTONS_CONFIG"
  touch -t 202001010000 "$ZSH_BUTTONS_STATE/cache"
  _zb_log_command second
  _zb_load_order

  assert_equal 2 "${#_zb_heads}" 'underfilled automatic button count' || return
)

test_automatic_mode_ranks_logged_commands || exit 1
test_automatic_mode_uses_recency_to_break_ties || exit 1
test_automatic_mode_applies_ignores_and_pins || exit 1
test_automatic_mode_learns_followups_without_adding_chains || exit 1
test_manual_mode_uses_only_configured_candidates || exit 1
test_manual_mode_keeps_chain_buttons || exit 1
test_cache_version_forces_automatic_refresh || exit 1
test_invalid_mode_fails_during_setup || exit 1
test_leading_space_keeps_a_command_out_of_the_log || exit 1
test_multiline_command_stays_out_of_automatic_ranking || exit 1
test_tabbed_command_stays_out_of_automatic_ranking || exit 1
test_underfilled_cache_adds_new_commands_before_daily_refresh || exit 1
print 'PASS: ranking'
