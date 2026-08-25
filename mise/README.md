# mise

Global [mise](https://mise.jdx.dev/) configuration, stowed to `~/.config/mise/config.toml`.

This is the single source of truth for CLI tools and language runtimes.
It is cross-platform: the same config installs the same tools on macOS
and Linux, which is what makes the POSIX/Lima path cheap to keep.

## Division of labour

- **mise** (this file): CLI tools distributed as single binaries, plus
  language runtimes (node, etc.).
- **Brewfile**: macOS-only things — casks, fonts, Mac App Store apps,
  and formulae that are genuinely better from Homebrew (git, neovim,
  tmux, zsh plugins).
- **Native installers**: AI CLIs (claude, codex, opencode, copilot)
  self-update aggressively; they are managed by their own installers.

## Usage

```bash
mise install    # install everything declared here
mise outdated   # check whether pinned tools have newer releases
mise upgrade --bump  # deliberately update pins and install newer releases
mise ls         # show what is installed and active
```

Tool versions are intentionally pinned in `config.toml`. Use `mise-bump` (or
`mise upgrade --bump`) as a deliberate maintenance action rather than allowing
routine updates to silently change the toolchain.
