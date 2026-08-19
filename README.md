# zsh-buttons

Buttons for the commands you run most, drawn when you open a shell. Arrow over to one and hit enter.

```
  ╭──────────────────────╮  ┌──────────────────────┐  ┌──────────────────────┐
  │                      │  │                      │  │                      │
  │        claude        │  │    login <input>     │  │       git pull       │
  │                      │  │                      │  │                      │
  ╰──────────────────────╯  └──────────────────────┘  └──────────────────────┘
  ┌──────────────────────┐  ┌──────────────────────┐  ┌──────────────────────┐
  │                      │  │                      │  │                      │
  │       wts main       │  │         dev          │  │     wts <input>      │
  │                      │  │                      │  │                      │
  └──────────────────────┘  └──────────────────────┘  └──────────────────────┘
  ┌──────────────────────┐  ┌──────────────────────┐  ┌──────────────────────┐
  │                      │  │     wts <input>      │  │                      │
  │     wtc <input>      │  │          &&          │  │       briefing       │
  │                      │  │        claude        │  │                      │
  └──────────────────────┘  └──────────────────────┘  └──────────────────────┘
  ←→ ↑↓ tab  ·  ⏎ run  ·  1-9 jump  ·  type to dismiss
```

Nine slots, ranked by how often you've actually run each one over the last 30 days. Whatever
you're using this week drifts to the front, whatever you've stopped using drops off, and you
don't have to remember an alias for any of it.

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

Then write `~/.config/zsh-buttons/config.zsh`:

```zsh
buttons_add claude
buttons_add codex
buttons_add 'git status'
buttons_add 'git checkout'      --arg
buttons_add 'docker compose up' --label 'compose up'
```

There's a longer starting point in `config.example.zsh`.

## Config

`buttons_add <cmd>` adds a button that runs the command.

`--arg` means the command needs an argument, so enter prefills your prompt with `<cmd> `
instead of running it. The box shows `<cmd> <input>`.

`--label <text>` sets the display name, for commands too long to fit.

`buttons_pin <cmd>` keeps a button first no matter how little you use it, which is also how
you protect a button you just added from being ranked off the grid before you've used it. It
still needs its own `buttons_add` line.

Arrows and tab move, enter picks, 1-9 jump straight to a button. Anything else dismisses the
buttons and starts your prompt with whatever you typed, so you can open a shell and just start
typing like normal.

## Chains

If you keep running two of your buttons back to back, the second one gets added to the first
and the pair shows up as its own button:

```
  ┌──────────────────────┐
  │     wts <input>      │
  │          &&          │
  │        claude        │
  └──────────────────────┘
```

Enter on that one puts `wts  && claude` on your prompt with the cursor sitting where the
branch name goes. Chains are found in your own history, so nothing appears that you didn't
already put on a button yourself, and a chain you press keeps its own place in the ranking.

## Follow-ups

When a button has more than one thing you habitually do next, it can't pick one, so it offers
them after the command finishes:

```
  ❯ wts main
  ┌──────────────────────┐  ┌──────────────────────┐
  │       git pull       │  │        claude        │
  └──────────────────────┘  └──────────────────────┘
  ←→ ⏎ run  ·  type to dismiss
```

This is why `git status` never offers anything. What you do after reading it depends on what
it said, so no single command follows it often enough to count.

## Settings

Set these in `.zshrc` before sourcing, or in your config file. Defaults:

```zsh
ZSH_BUTTONS_CMD=f                    # command to bring the buttons back
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

## License

MIT
