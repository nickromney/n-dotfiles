# Herdr configuration

Herdr runs inside Ghostty, so Ghostty remains the source of truth for the
terminal font and ANSI colours. The config selects Herdr's `terminal` theme,
which follows that host palette; with this repo's Ghostty config that means
Dimmed Monokai. Agent status uses symbols as well as colour, which is easier
to distinguish for colour-blind users.

Herdr has first-class workspaces, tabs, and panes. Its native `prefix+c`
shortcut, or the `+` button in the tab row, creates a new tab in the current
space. `terminal.new_cwd = "follow"` keeps the new tab in the current pane's
directory, so there is no need to create a workspace manually first.

## Installation

```bash
./stow.sh herdr
herdr server reload-config
```

The `herdr` CLI is managed in `mise/.config/mise/config.toml`.

For a Git checkout, Herdr's built-in worktree command is the appropriate
workspace-opening primitive:

```bash
herdr worktree open --cwd "$PWD" --path "$PWD" --focus
```

That operation reuses an already-open workspace for the checkout. After it
returns a workspace ID, `herdr tab list --workspace ID` and `herdr tab create
--workspace ID --label NAME --focus` provide the corresponding tab operations.
