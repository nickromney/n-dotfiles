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
