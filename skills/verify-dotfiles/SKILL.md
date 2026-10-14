---
name: verify-dotfiles
description: Verify n-dotfiles Stow behavior using GNU Stow and an isolated temporary home.
---

# Verify n-dotfiles

Run the harness from the repository root:

```bash
make verify-dry-run
make verify-test
make verify
```

The live cycle needs GNU Stow. It runs the repository's real `stow.sh git`
command with `HOME` scoped to a fresh directory under the run state. It proves that
the user's Git configuration path (`~/.gitconfig`) becomes a symlink to the
repository package and that the linked file exposes the expected `[user]` and
`[alias]` sections. It never applies packages to the invoking user's home.

The cycle removes only its run state. Evidence remains under
`${VERIFY_EVIDENCE_ROOT:-${VERIFY_BASE_DIR:-${TMPDIR:-/tmp}/verify-n-dotfiles}}/<run-id>/`.
The evidence includes the checkout revision and dirty status, Stow version,
Stow output, and a readback of the linked Git configuration. Set
`VERIFY_BASE_DIR`, `VERIFY_EVIDENCE_ROOT`, or `VERIFY_RUN_ID` to select isolated
locations and a stable run id.
