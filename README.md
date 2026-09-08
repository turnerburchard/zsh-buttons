# zsh-buttons

Buttons for the commands you run most, drawn when you open a shell. Arrow over to one and hit enter.

```
  ╭──────────────────────╮  ┌──────────────────────┐  ┌──────────────────────┐
  │                      │  │                      │  │                      │
  │        claude        │  │       wts main       │  │        codex         │
  │                      │  │                      │  │                      │
  ╰──────────────────────╯  └──────────────────────┘  └──────────────────────┘
  ┌──────────────────────┐  ┌──────────────────────┐  ┌──────────────────────┐
  │                      │  │                      │  │                      │
  │         wts          │  │        login         │  │        zed .         │
  │                      │  │                      │  │                      │
  └──────────────────────┘  └──────────────────────┘  └──────────────────────┘
  ┌──────────────────────┐  ┌──────────────────────┐  ┌──────────────────────┐
  │                      │  │                      │  │                      │
  │          gp          │  │       db-prod        │  │      git status      │
  │                      │  │                      │  │                      │
  └──────────────────────┘  └──────────────────────┘  └──────────────────────┘
  ←→ ↑↓ tab  ·  ⏎ run  ·  1-9 jump  ·  type to dismiss
```

Nine slots, filled from the commands you've actually run over the last 30 days. Counts decide
the order, with the most recently used command winning a tie. Whatever you've stopped using
drops off without a config edit.

zsh only. Tested in Ghostty, but it doesn't rely on anything Ghostty-specific.

## Install

```zsh
git clone https://github.com/turnerburchard/zsh-buttons ~/.zsh-buttons
```

Source it from the end of your `.zshrc`:

```zsh
source ~/.zsh-buttons/zsh-buttons.plugin.zsh
```

It has to go last, after anything that sets your shell up lazily (mise, nvm, fzf, zoxide). The
buttons draw on the first prompt, so a button pressed before your version manager has loaded
runs against the wrong node. Plugin managers are fine as long as this is the last entry.

No config is required. The first prompt builds the grid from the command log, which starts
empty and fills as you work.

An optional `~/.config/zsh-buttons/config.zsh` can pin or ignore exact commands:

```zsh
buttons_pin claude
buttons_ignore 'git pull'
```

Pinned commands stay first and are included even before they appear in the log. Ignored
commands are removed from ranking. Start a sensitive command with a space to keep it out of
the log entirely.

## Manual mode

Set `ZSH_BUTTONS_MODE=manual` when you want the grid to use only configured candidates:

```zsh
ZSH_BUTTONS_MODE=manual

buttons_pin claude
buttons_add claude
buttons_add codex
buttons_add 'git checkout'      --arg
buttons_add 'docker compose up' --label 'compose up'
```

`buttons_add <cmd>` adds a manual candidate that runs the command.

`--arg` means the command needs an argument, so enter prefills your prompt with `<cmd> `
instead of running it. The box shows `<cmd> <input>`.

`--label <text>` sets the display name, for commands too long to fit.

In manual mode, a pinned command still needs its own `buttons_add` line.

Arrows and tab move, enter picks, 1-9 jump straight to a button. Anything else dismisses the
buttons and starts your prompt with whatever you typed, so you can open a shell and just start
typing like normal.

## Chains

In manual mode, two configured buttons that you keep running back to back can earn a combined
button:

```
  ┌──────────────────────┐
  │     wts <input>      │
  │          &&          │
  │        claude        │
  └──────────────────────┘
```

Enter on that one puts `wts  && claude` on your prompt with the cursor sitting where the
branch name goes. Automatic mode keeps the startup grid to nine literal commands, so chains
do not take their slots.

## Follow-ups

When a button has a habitual next command, it can offer that command after the first one
finishes:

```
  ❯ wts main
  ┌──────────────────────┐  ┌──────────────────────┐
  │       git pull       │  │        claude        │
  └──────────────────────┘  └──────────────────────┘
  ←→ ⏎ run  ·  type to dismiss
```

Automatic mode learns follow-ups among the current top nine. Manual mode learns them among
configured candidates.

## Settings

Set these in `.zshrc` before sourcing, or in your config file. Defaults:

```zsh
ZSH_BUTTONS_CMD=f                    # command to bring the buttons back
ZSH_BUTTONS_MODE=automatic           # automatic or manual ranking
ZSH_BUTTONS_SLOTS=9                  # buttons on the grid
ZSH_BUTTONS_WINDOW_DAYS=30           # how far back usage counts
ZSH_BUTTONS_REFRESH_HOURS=24         # how often the order is recalculated
ZSH_BUTTONS_MAX_PER_ROW=3
ZSH_BUTTONS_CONFIG=~/.config/zsh-buttons/config.zsh
ZSH_BUTTONS_STATE=~/.local/share/zsh-buttons
```

`f` is the default because it's an easy key to hit. Set `ZSH_BUTTONS_CMD=` empty to bind
nothing and call `zsh_buttons` yourself.

The order is only recalculated once a day, so buttons don't shuffle around under you while
you're working. Editing your config also triggers a recalculation.

Every command you run gets appended to `$ZSH_BUTTONS_STATE/commands.log` along with a
timestamp and the directory. It never leaves your machine, and deleting it just resets the
ordering and forgets any chains.

## Tests

Run the ranking and interactive terminal tests with:

```zsh
zsh tests/run.zsh
```

## License

MIT
