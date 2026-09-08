# Copy to ~/.config/zsh-buttons/config.zsh when you want automatic ranking overrides.
#
#   buttons_pin <cmd>     always first, in the order pinned
#   buttons_ignore <cmd>  excluded from automatic ranking
#
# Automatic ranking is the default, so this file can be empty or absent.

buttons_pin claude
buttons_ignore 'git pull'

# Manual mode uses only commands added here:
# ZSH_BUTTONS_MODE=manual
# buttons_add claude
# buttons_add codex
# buttons_add 'git status'
# buttons_add 'git checkout'      --arg
# buttons_add 'docker compose up' --label 'compose up'
