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
mise outdated --bump  # check for releases beyond exact pins
make mise-bump-preview  # preview updates with a seven-day cooldown
make mise-bump  # update pins and install releases at least seven days old
mise ls         # show what is installed and active
```

Tool versions are intentionally pinned in `config.toml`. Run these Make targets
from the repository root. For an urgent security fix, use
`make mise-bump MISE_MINIMUM_RELEASE_AGE=0d MISE_BUMP_TOOLS="node bun"`.
Use the same variables with `mise-bump-preview` first. The override applies only
to that invocation. Exact version requests bypass mise's age filter; review
publication dates yourself when choosing explicit versions. See the root
[README](../README.md#adding-a-cli-tool) for the security update procedure.
