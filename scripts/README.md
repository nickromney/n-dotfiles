# Scripts

## update-all

Update the repo-managed toolchain and dependencies with a seven-day cooldown
for mise, Bun, and uv. The emergency override lasts for one invocation.

```bash
make update-all-preview
make update-all-preview NO_COOLDOWN=1
make update-all NO_COOLDOWN=1 NO_INPUT=1
make update-dependencies NO_COOLDOWN=1 NO_INPUT=1
```

Use `make update-mise`, `make update-brew`, `make update-mas`, or
`make update-rust` to select other components. Add `DRY_RUN=1` for a preview.
The shell script implements these Make targets; Make is the public entrypoint.
Self-updating Homebrew casks keep their native updater and release channel.
Forced greedy replacements are excluded because stale Homebrew receipts can
cause an app downgrade, including beta/nightly to stable. Homebrew, App Store, and Rust follow their native policies.
Previews can refresh registry caches, but do not install tools or write pins
or lockfiles. Homebrew previews use existing metadata. Failed steps produce
a nonzero exit status; independent steps still run. Dependencies are audited,
and the compiled browser tool is rebuilt and smoke-tested. Old mise versions and
Homebrew caches are retained. See the root [README](../README.md#adding-a-cli-tool)
for coverage and separate OS, AI CLI, and running-process updates.

## cleanup-storage

Preview global caches, or explicitly select projects and review workspaces.
The default is a dry run. `--all` keeps its existing global cache scope.

```bash
./scripts/cleanup-storage.sh --project-caches ~/Developer/personal --dry-run
./scripts/cleanup-storage.sh --project-caches ../multi-review/implementation --dry-run
./scripts/cleanup-storage.sh --project-caches ../multi-review/implementation --execute --no-input
```

Project discovery works under any directory. It clears only recognized ignored
caches in Git projects, including Terraform providers/modules, Swift build output,
uv caches, virtual environments, Node dependencies and common compiler caches.
Tracked and nonignored untracked files prevent removal of their cache directory.
Nested Git stores, reports, evidence, Swift build logs and result bundles stay.
Terraform backend state, environment selection and lockfiles stay.
Ordinary ignored local data stays. Symlinked roots and cache paths are refused.
Close builds and tools before execution; later use rebuilds or downloads caches.

To retire temporary checkouts, select a root containing them and a separate
recovery directory. Reports and other files outside individual checkouts stay.

```bash
./scripts/cleanup-storage.sh --retire-checkouts /path/to/review-workspace/implementation \
  --archive-root /path/to/recovery --dry-run
./scripts/cleanup-storage.sh --retire-checkouts /path/to/review-workspace/implementation \
  --archive-root /path/to/recovery --execute --no-input
```

Before removing each checkout, retirement archives its complete Git directory,
staged and unstaged changes, untracked files, and ignored noncache files.
Only the previewed disposable caches are omitted. It verifies archive contents,
permissions and symlinks, then checks that the source has stayed unchanged.
The recovery directory holds archives and manifests recording their source and
omitted caches. Allow enough free space for the archive before reclaiming a
checkout. Linked worktrees and external Git object stores require separate care.

Restore an archive into an empty directory:

```bash
mkdir /path/to/restored-checkout
tar -xzf /path/to/recovery/CHECKOUT.tar.gz -C /path/to/restored-checkout
git -C /path/to/restored-checkout status
```

Project modes need Python 3.9+ and Git. They cannot be mixed with the global
targets, `--report`, `--list` or the interactive chooser. Repeat a project flag
to select separate roots; overlapping roots are rejected before changes.

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

## sync-private-harness-assets

Reconcile selected private harness assets from the optional sibling
`../harnesses-private` repo into the Claude harness view. The selected Josh
Pigford, Matt Pocock, and JSM skills from `load/global.txt` are also exposed through the shared
global and Codex views; other private providers remain Claude-only.
The script links individual skill directories, skips cleanly when the private
repo is absent, removes stale private links, and discovers provider-grouped catalogs such as
`mattpocock/skills/tdd`, `joshpigford/skills/example`, and
`agents/skills/use-platform`. If a provider has `load/*.txt` manifests, only
listed skills are exposed. Supported manifests are `load/global.txt`,
`load/claude.txt`, and `load/codex.txt`. Duplicate loaded skill names are
namespaced as `<provider>-<skill>` in the flat harness roots.

Run from the `n-dotfiles` repo root. The default private source is
`../harnesses-private`; pass `--private-root <path>` for another location.

```bash
./scripts/sync-private-harness-assets.sh --dry-run
./scripts/sync-private-harness-assets.sh --execute
./scripts/sync-private-harness-assets.sh --dry-run --private-root ../harnesses-private
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

## audit-system-tools

Create a report-only deep inventory of Homebrew formulae/casks, mise status,
PATH directories and shadowing, application bundles, and curated overlapping
CLI candidates. It never removes anything.

```bash
./scripts/audit-system-tools.sh
./scripts/audit-system-tools.sh --out-dir /tmp/n-dotfiles-system-audit
```

## configure-audio-priority-bar

Apply the stable preferences from the `audio-priority-bar` Stow package into
the app's UserDefaults domain without replacing its volatile device cache.
AudioPriorityBar's sibling repository owns building, installation, release,
and notarisation.

```bash
./scripts/configure-audio-priority-bar.sh --dry-run
./scripts/configure-audio-priority-bar.sh
```

## macos-memory-report

Measure related macOS app process families with physical footprint as the
primary metric and RSS as a secondary diagnostic. The default report covers
AeroSpace, Borders, Bartender, Homerow, Superkey, AudioPriorityBar,
Pearcleaner, Bloom, Chops, Clearly, Spokenly, Wispr Flow, Brave, Google Chrome,
Docker Desktop, Silo, Ghostty, and RubyMine. It never quits or changes an app.

```bash
./scripts/macos-memory-report.sh
./scripts/macos-memory-report.sh --count 12 --interval 300
./scripts/macos-memory-report.sh --format tsv > /tmp/mac-memory.tsv
```

Repeated samples expose growth that a one-shot Activity Monitor reading can
miss. `Peak sum MiB` is an upper bound because each process may have reached
its lifetime peak at a different time.

For a repeatable comparison, keep the same tabs/project open, let startup
settle, then capture an idle plateau, the same representative task, and a
post-task plateau:

```bash
./scripts/macos-memory-report.sh --format tsv --count 12 --interval 5 \
  > /tmp/memory-trial.tsv
```

Use separate trial files for dictation (the same spoken passage in Spokenly
and Wispr Flow), Brave (the same tabs before and after the opt-in policy), and
Silo/Ghostty/RubyMine (the same project, file, terminal command, and build).
Compare `footprint_mib` first, then CPU and reload/latency observations.

## Borders

The `macos-borders` Stow package provides the default configuration and a small
CLI wrapper for the standalone `Borders.app`. It uses a single
WindowServer-rasterized ring, with an opaque bright yellow 5px stroke for
high-contrast colour-blind accessibility. The wrapper can use an existing
JankyBorders installation as an optional fallback:

```bash
$HOME/.local/bin/borders on
$HOME/.local/bin/borders off
$HOME/.local/bin/borders status
```

`off` hides the standalone app's overlays and starts JankyBorders when it is
installed. `reconcile` asks the app to reload its Stow-managed configuration.
The wrapper never builds the app itself.

The standalone checkout owns the app source, build, and release workflow. The
n-dotfiles bootstrap and `make install` flows run
`scripts/install-borders.sh`, which calls `make install` in
`~/Developer/personal/borders` when that checkout is present and otherwise
skip it.

The former Homebrew borders formula came from felixkratz/formulae. If that
retired tap is still installed, make update offers to remove it with a
non-force brew untap; an installed legacy formula is left for explicit
cleanup.

## configure-brave-memory

Brave supports Chromium's soft `TotalMemoryLimitMb` policy on macOS. This is
opt-in because exceeding the threshold discards inactive tabs and they may
reload after restart:

```bash
./scripts/configure-brave-memory.sh on --limit 2048
./scripts/configure-brave-memory.sh status
./scripts/configure-brave-memory.sh off
```

Use `--dry-run` to preview a change. The policy is not applied by setup.
