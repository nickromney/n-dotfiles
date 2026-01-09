# DevContainer Template (mise)

This template adds a DevContainer wired to mise for per-project tool versions.

## Usage

1. Copy this folder into your project as `.devcontainer/`.
2. Add a `mise.toml` in the project root with required tools.
3. Rebuild the DevContainer.

## Mounts

The template includes a small set of explicit host mounts:

- `~/.ssh` mounted read-only to `/home/vscode/.ssh`.
- `~/.gitconfig` mounted read-only to `/home/vscode/.gitconfig`.
- A named Docker volume at `/mnt/mise-data` for shared mise caches.

Remove any mounts you do not want to expose to containers.

## Notes

- `MISE_DATA_DIR` points at `/mnt/mise-data` and `PATH` includes `/mnt/mise-data/shims`.
- `postCreate.sh` adds `mise activate` lines to `.bashrc` and `.zshrc` if missing.
- `postStart.sh` runs `mise install` when a `mise.toml` is present.

## Two-way Door

To roll back, delete `.devcontainer/` from the project and remove the named volume
(`mise-data-volume`) if you no longer want cached tool downloads.
