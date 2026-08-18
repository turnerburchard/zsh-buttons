# zsh-buttons

Buttons for the commands you run most, drawn when you open a shell. Arrow over to one and hit enter.

```
  ╭────────────────╮  ┌────────────────┐  ┌────────────────┐  ┌────────────────┐
  │     claude     │  │     codex      │  │   git status   │  │    git pull    │
  │                │  │                │  │                │  │                │
  ╰────────────────╯  └────────────────┘  └────────────────┘  └────────────────┘
  ┌────────────────┐  ┌────────────────┐  ┌────────────────┐  ┌────────────────┐
  │  git checkout  │  │  npm run dev   │  │    npm test    │  │   compose up   │
  │    <branch>    │  │                │  │                │  │                │
  └────────────────┘  └────────────────┘  └────────────────┘  └────────────────┘
  ←→ ↑↓ tab  ·  ⏎ run  ·  1-8 jump  ·  type to dismiss
```

They're ordered by how often you've actually run each one over the last 30 days, so whatever
you're using this week drifts to the front and you don't have to remember an alias for it.

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
buttons_add 'git checkout'      --arg '<branch>'
buttons_add 'docker compose up' --label 'compose up'
```

There's a longer starting point in `config.example.zsh`.

## Config

`buttons_add <cmd>` adds a button that runs the command.

`--arg '<hint>'` means the command needs an argument, so enter prefills your prompt with
`<cmd> ` instead of running it. The hint shows in the box.

`--label <text>` sets the display name, for commands too long to fit.

`buttons_pin <cmd>` keeps a button first no matter how little you use it. It still needs its
own `buttons_add` line.

Arrows and tab move, enter picks, 1-9 jump straight to a button. Anything else dismisses the
buttons and starts your prompt with whatever you typed, so you can open a shell and just start
typing like normal.

## Settings

Set these in `.zshrc` before sourcing, or in your config file. Defaults:

```zsh
ZSH_BUTTONS_CMD=f                    # command to bring the buttons back
ZSH_BUTTONS_WINDOW_DAYS=30           # how far back usage counts
ZSH_BUTTONS_REFRESH_HOURS=24         # how often the order is recalculated
ZSH_BUTTONS_MAX_PER_ROW=4
ZSH_BUTTONS_CONFIG=~/.config/zsh-buttons/config.zsh
ZSH_BUTTONS_STATE=~/.local/share/zsh-buttons
```

`f` is the default because it's an easy key to hit. Set `ZSH_BUTTONS_CMD=` empty to bind
nothing and call `zsh_buttons` yourself.

The order is only recalculated once a day, so buttons don't shuffle around under you while
you're working. Editing your config also triggers a recalculation.

Every command you run gets appended to `$ZSH_BUTTONS_STATE/commands.log` along with a
timestamp and the directory. It never leaves your machine, and deleting it just resets the
ordering.

## License

MIT
