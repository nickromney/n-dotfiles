# Codex Agent Guide (n-dotfiles)

**Purpose**: Operate safely in this repo, follow house style, and keep changes minimal,
reviewable, and idempotent.

## Quick Rules

- Read this file before major decisions; re-skim if requirements change.
- Keep commands short-lived; if something runs >5 minutes, stop and ask.
- Git is read-only unless the user explicitly asks for commits, pushes, or branches.
- No destructive operations unless the user explicitly approves.
- Fix root causes, avoid bandaids. Remove dead code instead of leaving breadcrumbs.
- Use `trash` for deletes when available.

## Repo Map

- `_configs/`: YAML bundles (shared, host, focus) used by `install.sh` and Makefile profiles.
- `_macos/`: macOS defaults scripts + per-profile YAML; change settings here, not manually.
- `_test/`: Bats suites, helpers, and runners (`run_tests.sh`, `shellcheck.sh`).
- Tool dirs (`nvim/`, `kitty/`, `tmux/`, `zsh/`, etc.) mirror final paths for GNU Stow.

## Common Commands

- `./bootstrap.sh`: prepare a fresh macOS host (Homebrew, Stow, baseline packages).
- `./install.sh [-d|-s|-u]`: core installer (dry-run, stow, update tools).
- `make common|personal|work install`: run Makefile bundles.
- `make app-store install`: optional App Store apps (after signing in).
- `make test` or `_test/run_tests.sh`: full Bats matrix.
- `make precommit`: run all pre-commit hooks.

## Coding Style

- Bash scripts: `set -euo pipefail`, two-space indent, snake_case functions, `[[ ... ]]`.
- Keep logic idempotent; guard external dependencies (see `REQUIRED_COMMANDS`).
- Prefer `rg` for search; use `ast-grep` for AST-safe edits when it helps.
- Keep files reasonable in size; split large files rather than expanding past ~500 LOC.

## Testing

- Tests live in `_test/*.bats`; mock via `_test/helpers` rather than touching the host OS.
- Run `_test/shellcheck.sh` after shell edits; fix issues rather than silencing.
- Prefer targeted runners while iterating (`_test/run_install_tests.sh`, `_test/run_macos_tests.sh`).

## Workflow & Safety

- Use repo task runners: prefer `just` if present, otherwise the `Makefile`.
- If a new dependency is needed, research maintained options and confirm with the user.
- Secrets never belong in dotfiles; use the 1Password-backed setup scripts.
- When adding package managers or credentials, update `REQUIRED_COMMANDS`, dry-run handling,
  and docs so `./install.sh -d` stays safe without sudo.

## Git & PR Guidance

- Conventional Commits (`feat:`, `fix:`, `chore:`, `docs:`) under ~70 chars.
- Use `gh` for PR/CI info; avoid opening URLs.
- Keep changes small and focused; avoid repo-wide search/replace scripts.

## Communication

- Be terse; noun-phrases are fine. Avoid filler.
- Prefer dry, low-key humor only if it will land.
- If you are unsure, ask with short options rather than guessing.

## Tooling Notes

- Web search early when blocked; prefer official docs and current sources.
- MCP via `mcporter` is allowed; if it is not installed, use `npx mcporter <server>`.

### Using bv as an AI sidecar

bv is a graph-aware triage engine for Beads projects (.beads/beads.jsonl). Instead of parsing JSONL or hallucinating graph traversal, use robot flags for deterministic, dependency-aware outputs with precomputed metrics (PageRank, betweenness, critical path, cycles, HITS, eigenvector, k-core).

**Scope boundary:** bv handles _what to work on_ (triage, priority, planning). For agent-to-agent coordination (messaging, work claiming, file reservations), use [MCP Agent Mail](https://github.com/Dicklesworthstone/mcp_agent_mail).

**⚠️ CRITICAL: Use ONLY `--robot-*` flags. Bare `bv` launches an interactive TUI that blocks your session.**

#### The Workflow: Start With Triage

**`bv --robot-triage` is your single entry point.** It returns everything you need in one call:

- `quick_ref`: at-a-glance counts + top 3 picks
- `recommendations`: ranked actionable items with scores, reasons, unblock info
- `quick_wins`: low-effort high-impact items
- `blockers_to_clear`: items that unblock the most downstream work
- `project_health`: status/type/priority distributions, graph metrics
- `commands`: copy-paste shell commands for next steps

bv --robot-triage # THE MEGA-COMMAND: start here
bv --robot-next # Minimal: just the single top pick + claim command

#### Other Commands

**Planning:**

| Command            | Returns                                         |
| ------------------ | ----------------------------------------------- |
| `--robot-plan`     | Parallel execution tracks with `unblocks` lists |
| `--robot-priority` | Priority misalignment detection with confidence |

**Graph Analysis:**

| Command                                         | Returns                                                                                                                              |
| ----------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------ |
| `--robot-insights`                              | Full metrics: PageRank, betweenness, HITS (hubs/authorities), eigenvector, critical path, cycles, k-core, articulation points, slack |
| `--robot-label-health`                          | Per-label health: `health_level` (healthy\|warning\|critical), `velocity_score`, `staleness`, `blocked_count`                        |
| `--robot-label-flow`                            | Cross-label dependency: `flow_matrix`, `dependencies`, `bottleneck_labels`                                                           |
| `--robot-label-attention [--attention-limit=N]` | Attention-ranked labels by: (pagerank × staleness × block_impact) / velocity                                                         |

**History & Change Tracking:**

| Command                           | Returns                                                                                                |
| --------------------------------- | ------------------------------------------------------------------------------------------------------ |
| `--robot-history`                 | Bead-to-commit correlations: `stats`, `histories` (per-bead events/commits/milestones), `commit_index` |
| `--robot-diff --diff-since <ref>` | Changes since ref: new/closed/modified issues, cycles introduced/resolved                              |

**Other Commands:**

| Command                                             | Returns                                                            |
| --------------------------------------------------- | ------------------------------------------------------------------ |
| `--robot-burndown <sprint>`                         | Sprint burndown, scope changes, at-risk items                      |
| `--robot-forecast <id\|all>`                        | ETA predictions with dependency-aware scheduling                   |
| `--robot-alerts`                                    | Stale issues, blocking cascades, priority mismatches               |
| `--robot-suggest`                                   | Hygiene: duplicates, missing deps, label suggestions, cycle breaks |
| `--robot-graph [--graph-format=json\|dot\|mermaid]` | Dependency graph export                                            |
| `--export-graph <file.html>`                        | Self-contained interactive HTML visualization                      |

#### Scoping & Filtering

bv --robot-plan --label backend # Scope to label's subgraph
bv --robot-insights --as-of HEAD~30 # Historical point-in-time
bv --recipe actionable --robot-plan # Pre-filter: ready to work (no blockers)
bv --recipe high-impact --robot-triage # Pre-filter: top PageRank scores
bv --robot-triage --robot-triage-by-track # Group by parallel work streams
bv --robot-triage --robot-triage-by-label # Group by domain

#### Understanding Robot Output

**All robot JSON includes:**

- `data_hash` — Fingerprint of source beads.jsonl (verify consistency across calls)
- `status` — Per-metric state: `computed|approx|timeout|skipped` + elapsed ms
- `as_of` / `as_of_commit` — Present when using `--as-of`; contains ref and resolved SHA

**Two-phase analysis:**

- **Phase 1 (instant):** degree, topo sort, density — always available immediately
- **Phase 2 (async, 500ms timeout):** PageRank, betweenness, HITS, eigenvector, cycles — check `status` flags

**For large graphs (>500 nodes):** Some metrics may be approximated or skipped. Always check `status`.

#### jq Quick Reference

bv --robot-triage | jq '.quick_ref' # At-a-glance summary
bv --robot-triage | jq '.recommendations[0]' # Top recommendation
bv --robot-plan | jq '.plan.summary.highest_impact' # Best unblock target
bv --robot-insights | jq '.status' # Check metric readiness
bv --robot-insights | jq '.Cycles' # Circular deps (must fix!)
bv --robot-label-health | jq '.results.labels[] | select(.health_level == "critical")'

**Performance:** Phase 1 instant, Phase 2 async (500ms timeout). Prefer `--robot-plan` over `--robot-insights` when speed matters. Results cached by data hash.

Use bv instead of parsing beads.jsonl—it computes PageRank, critical paths, cycles, and parallel tracks deterministically.
