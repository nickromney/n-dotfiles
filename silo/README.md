# Silo configuration

This Stow tree manages two files under `~/.config/silo`:

- `app-state.json` — Silo's preference store. It holds the terminal font,
  the active theme, editor and terminal settings, and workspace ordering. It
  also accumulates machine-local churn (active workspace, per-terminal agent
  state), so expect noisy diffs.
- `themes/620a047e-a81b-4f4a-a238-ace13966c729.json` — a custom **Dimmed
  Monokai** theme derived from the Ghostty theme in
  `ghostty/.config/ghostty/config`. Stowing it makes it available in Silo's
  theme picker.

Workspace definitions (`~/.config/silo/workspaces/`), installed extensions,
terminal buffers, and the session registry are machine-local and deliberately
not managed here.

## Font

`terminalSettings.fontFamily` in `app-state.json` should be set to `Monaco`.

This is a constraint of Silo, not a preference. Silo is a Tauri app, so its
terminal renders in a WKWebView, and it sizes its character grid by canvas
text measurement. **WebKit does not expose user-installed fonts to canvas
measurement**, only to DOM layout, as a fingerprinting protection. Measured
per-character advance at 100px:

| Font                     | Canvas | DOM   |
| ------------------------ | ------ | ----- |
| JetBrainsMono Nerd Font  | 88.92  | 60.00 |
| Fira Code                | 88.92  | 61.54 |
| Monaco                   | 60.01  | 60.01 |
| Menlo                    | 60.21  | 60.21 |
| a nonexistent font       | 88.92  | 88.92 |

Any font installed in `~/Library/Fonts` or `/Library/Fonts` measures as the
fallback, so the terminal builds a 0.889em grid and paints 0.600em glyphs
into it. The result is badly loose tracking. Only fonts in the system font
directories measure consistently.

Monaco is the only system monospace carrying the Apple logo at U+F8FF, which
the shell prompt uses. Menlo lays out correctly but renders that glyph as
tofu. The cost of Monaco is that no other Nerd Font icon is available, so
powerline separators and devicons will tofu if the prompt gains them.

Silo also accepts a single family, not a fallback chain, so the Ghostty
fallbacks cannot be reproduced here.

Naming, if a user font is ever usable: WKWebView matches the typographic
family name, `JetBrainsMono Nerd Font`, not the short CoreText family
`JetBrainsMono NF` that `fc-list` reports and Ghostty accepts.

## Theme

`activeThemeId` is currently `tokyo-night`, one of Silo's built-in themes.
Silo also ships **High Contrast Dark** and **High Contrast Light**, which are
the best accessibility-oriented options in the built-in list. Solarized
Dark/Light are reasonable lower-glare choices, but none of these are dedicated
colour-blind modes.

## Installation

```bash
./stow.sh silo
```

Silo rewrites `app-state.json` as it runs. Quit Silo before restowing, and
check `git diff` before committing.
