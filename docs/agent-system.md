# n-dotfiles: agent operating model

Adopted 6 October 2026 from local source and command inspection.
Three-owner declarative machine setup and harness exposure.

## Read by intent

Start with the local agent guide and build manifest. For domain or behavior
changes, follow the owners below, then the relevant contract/test. These
documents retain product detail and historical evidence:

- [ghostty/README.md](../ghostty/README.md)
- [karabiner/README.md](../karabiner/README.md)
- [omarchy/README.md](../omarchy/README.md)
- [nvim/README.md](../nvim/README.md)
- [aws/.aws/README.md](../aws/.aws/README.md)

## System ownership

| Owner | Responsibility |
| --- | --- |
| [Brewfile](../Brewfile) | macOS/Linux Homebrew package intent. |
| [Brewfile.posix](../Brewfile.posix) | macOS/Linux Homebrew package intent. |
| [mise/.config/mise/config.toml](../mise/.config/mise/config.toml) | Cross-platform CLI/runtime intent. |
| [stow.sh](../stow.sh) | Dotfile and harness symlink intent. |
| [zsh](../zsh) | Dotfile and harness symlink intent. |
| [git](../git) | Dotfile and harness symlink intent. |
| [codex](../codex) | Dotfile and harness symlink intent. |

Intent selects the owning policy; that policy produces decisions or artifacts;
adapters perform effects; verification establishes the result. Change the
owner once and keep alternate surfaces on that same contract.

## Invariants

- Brew, mise and Stow remain separate owners.
- AI CLIs self-update outside package pins.
- Preserve owner changes and local conflict backups.

## Existing action interfaces

These are inspected command surfaces, not a report that they ran. Read current
help and recipes for arguments, dependencies and lifecycle hooks before use.
Examples containing placeholder paths or bracketed options are grammar.

| Command | Effects and evidence |
| --- | --- |
| `./stow.sh --list` | Discovers Stow package selection. |
| `./stow.sh --dry-run` | Previews symlinks/conflicts. |
| `./bootstrap.sh --dry-run --no-input --skip-1password` | Preview macOS bootstrap without attended secrets. |
| `make install` | Applies package/Stow/mise state; host mutation. |

## Observe, verify and retain

Establish source revision, dirty state and relevant input identity before
choosing an action. Keep intended settings, cached artifacts and observed
runtime state distinct. An existing artifact is not a freshness or readiness
claim. Use the smallest deterministic fixture at the changed seam first;
expand to process, browser, device or deployment checks only when that
claim needs them. Record unavailable evidence explicitly.

Retain the command/configuration, source and input identity, result, limitation
and next discriminating check. Reuse evidence only while its relevant inputs
remain applicable. Promote a reproducible failure to a regression fixture,
a design decision to its owning document, and a repeated operator correction
to one concise guide rule. Keep private observations in private artifacts.

## Implemented plan for this pass

- [x] Map current source ownership and existing interfaces.
- [x] Make command effects and evidence limits discoverable.
- [x] Route agent work here and retain detailed product plans at their owners.

Acceptance: owner paths and document links resolve; current instructions
match inspected source; catalog hashes bind this context to the reviewed
bytes. This is documentation/control navigation acceptance. Product runtime
checks retain their own scope and are not certified by this pass.

## Project decisions

Reason about package intent, runtime intent and symlink intent independently; inspect the owning declaration before choosing a setup command. Installed tools and symlinks are observed host state, not proof that every declared layer converged. Start with ./stow.sh --list and --dry-run or bootstrap preview, then scope application to the requested layer. Record platform, declaration revision, selected packages and backup paths when reviewing changes; never include 1Password values. Preserve user-edited configuration and existing conflict backups. Keep harness assets traceable through private catalogue source, explicit exposure manifest and actual symlink; do not duplicate provider-owned skills here. New setup lessons belong in the owning script/test or nearest platform README.
