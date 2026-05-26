# Scripts

## audit-github-repos

Compare a GitHub owner's repositories with local clones, then report upstream
changes and branch drift from `origin/main`. The GitHub repo list is cached for
24 hours by default; local repo state is checked on every `--execute` run.

```bash
./scripts/audit-github-repos.sh --dry-run
./scripts/audit-github-repos.sh --execute
./scripts/audit-github-repos.sh --execute --no-fetch
./scripts/audit-github-repos.sh --execute --refresh-cache
./scripts/audit-github-repos.sh --execute --exclude-file ~/.config/repo-audit/excludes.txt
```

## audit-local-git-repos

Fast local-only audit for directories that should each be Git repositories. It
scans one level under the target root, reports non-git directories, and compares
each repo's current branch with `origin/main` without network access by default.

```bash
./scripts/audit-local-git-repos.sh --dry-run
./scripts/audit-local-git-repos.sh --execute
./scripts/audit-local-git-repos.sh --execute --all
./scripts/audit-local-git-repos.sh --execute --root ~/Developer/work --format tsv
```

## audit-harness-guides

Read-only audit for repo-local harness guide files such as `AGENTS.md`,
`CLAUDE.md`, and `GEMINI.md`. It scans one level under the target root and
reports guide size metrics, repo-local skill references, and likely review
states.

```bash
./scripts/audit-harness-guides.sh --dry-run
./scripts/audit-harness-guides.sh --execute
./scripts/audit-harness-guides.sh --execute --all
./scripts/audit-harness-guides.sh --execute --root ~/Developer/work --format tsv
```

## list-non-owner-repos

Review local repos whose `origin` remote is not owned by an expected GitHub
owner:

```bash
./scripts/list-non-owner-repos.sh --dry-run
./scripts/list-non-owner-repos.sh --execute
./scripts/list-non-owner-repos.sh --execute --root ~/Developer/work --owner RNLI-Workspace
./scripts/list-non-owner-repos.sh --execute --format paths
```

## browser-tools

Standalone Chrome DevTools helper. Source lives at `scripts/browser-tools.ts`.

Build a local binary (not committed):

```bash
./scripts/build-browser-tools.sh
```

The build script will install `commander` and `puppeteer-core` in `scripts/node_modules` as needed.

Usage:

```bash
bin/browser-tools --help
```

Makefile target:

```bash
make browser-tools
```

## audit-installed

Compare globally installed Homebrew and npm artifacts with the repo-managed YAML
definitions, then write timestamped inventory files under `_audit/installed/`.
The `package-manager-surface.tsv` output traces each brew formula/cask and npm
global package to its owning package manager, repo-managed status, and direct
npm dependency footprint where package metadata is local.

```bash
./scripts/audit-installed.sh
./scripts/audit-installed.sh --out-base /tmp/n-dotfiles-audit
make audit-installed
```
