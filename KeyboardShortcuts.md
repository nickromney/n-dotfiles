# Keyboard shortcuts

This is the current keyboard model on the personal Mac. It records the
settings visible in AeroSpace, Superkey, and Homerow on 2026-08-06, rather
than only the intended setup.

## Modifier model

Superkey turns **Caps Lock** into **Hyper**:

```text
Hyper = Control + Option + Command + Shift
```

The physical Command key remains Command. Holding Caps Lock supplies Hyper;
quickly tapping Caps Lock sends Right Arrow, which accepts the current zsh
autosuggestion. Pressing Left Shift and Right Shift together toggles the real
Caps Lock state.

Superkey's active editing presets are:

- `Hyper + Delete` -> forward delete
- `Hyper + V` -> paste without formatting
- `Home` / `End` -> beginning / end of line
- `Left Shift + Right Shift` -> toggle Caps Lock

The Superkey Seek page currently has no shortcut or remapped key configured.
The older `Hyper + G` Seek mapping in this document was therefore historical,
not part of the inspected configuration.

## Homerow

### Clicking

- `Hyper + F` -> label clickable UI elements
- Automatic click: on
- Chain clicks: off
- Mission Control support: on
- Label characters: `SADFJKLEWCMPGH`
- Browser labels: Fast
- Search shortcut: not set

### Scrolling

- `Hyper + S` -> choose a scroll area
- Arrow keys select the scroll area
- Scroll-area numbers: on
- Scroll keys: `HJKL`
- Scroll commands: on
- Auto-deactivation: off
- Scroll speed: `1.0`
- Dash speed: `1.5`

### General

- Launch at login: on
- Menu-bar icon: on
- Automatic updates: on; beta updates: off
- Input source: British
- Homerow's own Hyperkey emulation: off (Superkey owns it)
- Sound effects: on, volume `0.6`

## AeroSpace

The source of truth is
[`aerospace/.config/aerospace/aerospace.toml`](aerospace/.config/aerospace/aerospace.toml).

### Focus and resize

- `Alt + H/J/K/L` -> focus left/down/up/right
- `Alt + Shift + -/=` -> resize by -/+100

### Named workspaces

| Key | Workspace | Typical apps |
|---|---|---|
| `Hyper + W` | Work | Chrome profiles |
| `Hyper + T` | Terminal | Ghostty, Kitty |
| `Hyper + Y` | Development | VS Code, Cursor, Codex, GitKraken |
| `Hyper + U` | Utilities | Finder, Preview, Docker, capture/device tools |
| `Hyper + I` | Internet | Brave, Safari, Firefox |
| `Hyper + O` | Office | Excel, Word |
| `Hyper + P` | Productivity | Notes, Obsidian, Things, Spotify, Claude |
| `Hyper + [` | Email | HEY, Outlook |
| `Hyper + ]` | Communication | Messages, Teams, WhatsApp, Slack, Zoom |

`Hyper + H` toggles the last two workspaces. `Hyper + L` moves the current
workspace to the next monitor.

### Move the current window and follow it

The number row mirrors the physical position of the workspace letters:

- `Hyper + 2/5/6/7/8/9/0/-/=` -> move to and focus
  `W/T/Y/U/I/O/P/[/]`

### Layout mode

- `Hyper + N` -> accordion layout
- `Hyper + M` -> tiled layout
- `Hyper + ;` -> enter move mode

Within move mode:

- `H/J/K/L` -> move the window
- `E` -> accordion layout
- `F` -> fullscreen
- `T` -> toggle floating/tiling and leave move mode
- `B` -> balance sizes
- `Escape` or `Enter` -> leave move mode

## Omarchy translation

The Mac workspace taxonomy is deliberately compressed to five numeric
workspaces on the smaller Omarchy laptop. Caps Lock still becomes Hyper, but
the physical Windows key remains Omarchy's Super key. See
[`omarchy/README.md`](omarchy/README.md) for the mapping and setup.
Workspace 2 is the coding stack: Cursor, terminals, Claude Code/Codex, and
Slicer agent shells.
