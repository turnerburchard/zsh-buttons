# Copy to ~/.config/zsh-buttons/config.zsh and put your own commands in.
#
#   buttons_add <cmd>                 runs the command
#   buttons_add <cmd> --arg           prefills the prompt instead of running
#   buttons_add <cmd> --label <text>  display name, for commands too long for a box
#   buttons_pin <cmd>                 always first, in the order pinned
#
# The grid holds 9 buttons, ranked by usage over the last 30 days and refreshed once a
# day. List more than 9 and the ones you don't use drop off. This file's order is the
# tiebreaker and the fallback before there's any usage data.

buttons_pin claude

buttons_add claude
buttons_add codex
buttons_add 'git status'
buttons_add 'git pull'
buttons_add 'git checkout'      --arg
buttons_add 'npm run dev'
buttons_add 'npm test'
buttons_add 'docker compose up' --label 'compose up'
