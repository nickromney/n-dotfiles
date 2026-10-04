# Repository audit — 3 October 2026

Status: audit and authorized remediation complete. All 27 verified findings have
fixes on the audit branch; historical metadata and validation limits are recorded below.
Six serious security findings, ten high correctness findings, nine medium/moderate
findings, and two low test/report defects were addressed. No active secret or
critical security finding was established.

## Goal and constraints

Audit the whole repository for reproducible correctness defects, security
problems, private information exposure, and duplication that causes real drift.
Fix verified issues one at a time and record the evidence and validation here.

- Preserve the original checkout's commits, staged changes, unstaged work, and untracked files.
- The audit kept Git read-only. The user then authorized a branch and PR in an
  isolated checkout; existing commits are not rewritten.
- Do not apply setup to the live machine or install global tools during the audit.
  Exception: the user explicitly approved the reviewed runtime-directory migration
  and source cleanup; that migration is now complete.
- Use temporary homes and mocked operating-system boundaries for verification.
- Keep intentional public author identity; remove private machine, employer,
  account, and infrastructure details where doing so preserves functionality.
- Never copy secret values into this report. Historical exposure requires a
  separate rotation/history decision; deleting current files cannot revoke it.

## Baseline

Starting commit: `e36f828` on `main`. There are 216 tracked paths.
Existing work at the start:

| Path | State |
| --- | --- |
| `AGENTS.md` | Unstaged edit |
| `CLAUDE.md` | Unstaged deletion |
| `README.md` | Staged and unstaged edits |
| `_test/cli-contracts.bats` | Staged and unstaged edits |
| `mise/.config/mise/config.toml` | Unstaged edit |
| `scripts/README.md` | Staged and unstaged edits |
| `scripts/sync-private-harness-assets.sh` | Staged and unstaged edits |
| `claude/.claude/CLAUDE.md` | Untracked |

Baseline diffs, file hashes, and HEAD were saved outside the repository in a
temporary audit directory. At the audit handoff, the original checkout's HEAD and
staged-diff comparisons were byte-for-byte unchanged. Every baseline dirty/untracked
path retained its saved hash except README, where narrow
security-promise corrections preserve the original harness section verbatim.

## Plan and review boundaries

1. Read architecture, entrypoints, configs, tests, CI, and current work in progress.
2. Independently audit setup safety, privacy/security, and validation/duplication.
3. Reproduce each candidate before adding it to the finding register.
4. Fix one issue per test-first slice, then record its outcome.
5. Run applicable focused checks, the full safe test suite, lint, and diff review.

The user approved these test boundaries on 3 October: public shell commands
(flags, exit codes, produced files), Stow behavior in temporary homes, and
documented config behavior. Tests will avoid private implementation details.

## Coverage

| Area | State |
| --- | --- |
| Bootstrap, Stow, macOS defaults, 1Password setup | Reviewed; fixes verified at temporary-home command boundaries |
| Tracked configs, private information, secret history | Reviewed; source protections and approved live migration complete |
| Maintenance scripts, hooks, CI, test harness | Reviewed; independent second pass complete |
| Shell startup, browser tooling, executable configs | Reviewed; focused portability/browser checks pass |
| Dependency advisories and documentation promises | Bun advisory scan complete; promises checked against code and primary docs |

## Finding register

Only verified actionable findings belong here. Severity, evidence, a concrete
fix, breakage risk, and validation accompany each entry. Security uses the
security skill's Serious/Moderate labels; correctness uses High/Medium/Low.
The register places serious security issues first, followed by high correctness
issues and the remaining findings. The user's whole-repo request explicitly extends
the diff-review skill to pre-existing code; the second pass also reviews our fixes.

| ID | Severity | Finding | State |
| --- | --- | --- | --- |
| A04 | Serious | Shellcheck gate uses predictable shared temporary output | Fixed; regression passes |
| A05 | Serious | Browser profile directory is evaluated as shell code | Fixed; regression passes |
| A06 | Serious | AWS/GH/Nushell runtime state can enter public Stow trees | Fixed; approved migration and source cleanup complete |
| A12 | Serious | Work Git config is world-readable and printed to logs | Fixed; regression passes |
| A13 | Serious | Security promises overstate storage, logging, and MFA guarantees | Corrected; documentation lint passes |
| A18 | Serious | Tracked Claude permissions carry private paths and broad stale grants | Sanitized and moved to shared policy; JSON validates |
| A01 | High | macOS dry-run writes Reduce Transparency | Fixed; focused test passes |
| A02 | High | Failed 1Password downloads remove active configs | Atomic replacement fixed; tests pass |
| A03 | High | Make reports successful tool installation/update after failure | Fixed; regression passes |
| A08 | High | CSV field output corrupts SSH key downloads | Fixed; realistic key tests pass |
| A09 | High | Browser profile copy deletes unrelated destination files | Fixed; regression passes |
| A10 | High | Tests invoke real credential and host-setting commands | Isolation fixed; regression passes |
| A14 | High | AWS helper selects a different local account or fails on Linux | Fixed; invoking-account regression passes |
| A15 | High | Nushell mise integration overwrites PATH with a personal Mac snapshot | Fixed; portability regression passes |
| A19 | High | Bootstrap installs 1Password despite its explicit skip flag | Fixed; regression passes |
| A20 | High | Legacy borders cleanup deletes an unrelated daemon file | Fixed; preservation regression passes |
| A07 | Medium | macOS show mode exits after listing its first application | Fixed; regression passes |
| A11 | Medium | Bash forces an unavailable locale on unprovisioned Linux | Fixed; regression passes |
| A16 | Medium | Tool audit compares Linux inventory with the Mac Brewfile | Fixed; focused regression passes |
| A17 | Medium | Duplicate Brewfile parsers misclassify declared casks | Fixed; six focused checks pass |
| A22 | Medium | Native macOS Bash crashes on empty optional arrays across maintenance commands | Fixed; native-shell regressions pass |
| A23 | Medium | Nushell syntax test accepts invalid configuration as success | Fixed; negative fixture passes |
| A24 | Medium | Harness audit relies on unavailable native-Bash mapfile | Fixed; native-shell regression passes |
| A25 | Moderate | Progress and build-agent plan disclose private machine inventory and paths | Sanitized; explicit prose lint passes |
| A27 | Moderate | Tracked audio preferences expose device-specific identifiers | Cleaned; local-priority preservation regression passes |
| A21 | Low | Harness audit mistakes ordinary prose for skill references | Fixed; regression passes |
| A26 | Low | Shell PATH test splits space-containing paths and reports false failure | Fixed; existing regression passes |

### A01 — macOS dry-run changes a live setting

- **Evidence:** `_macos/macos.sh` writes `reduceTransparency` directly, bypassing
  the dry-run-aware default-setting path. A minimal YAML profile plus mocked
  `defaults` records a `write` during `--dry-run --no-input`.
- **Fix:** Honor dry-run before attempting the accessibility preference write.
- **Breakage risk:** Low; execute mode must retain its permissions/help fallback.
- **Validation:** The new public-command test failed on the preference-write
  marker before the fix and passes afterward. Focused and final full-suite validation pass.

### A02 — Failed credential/config retrieval removes active configuration

- **Evidence:** Both 1Password setup commands redirect into the destination before
  retrieval succeeds. A failing mocked `op` removes an existing SSH config and
  work Git include; both commands still exit successfully. Backups exist, but the
  active configuration is lost until manually restored.
- **Fix:** Stage downloads in private temporary files; replace only complete,
  valid results and preserve existing active files on failure.
- **Breakage risk:** Low; genuinely missing items on a fresh machine must retain
  the documented template/skip behavior.
- **Validation:** Public-command failures preserve active base/profile SSH config,
  public keys, and the work Git include. Partial-download tests fail before the
  atomic fix and pass afterward. Tempfiles/backups use private permissions;
  malformed Git config is rejected before publication.

### A03 — Make masks installation and update failures

- **Evidence:** A `mise` mock exiting 42 makes `make mise-install mise-bump` exit
  zero and print success. The compound recipes continue to `echo`; `mas upgrade`
  and `rustup update` use the same pattern.
- **Fix:** Propagate the tool status before printing success or continuing.
- **Breakage risk:** Low; failed operations now stop with a nonzero status.
- **Validation:** Failing-tool tests at the public Make targets went red then
  green; success messages are absent after failure.

### A04 — Shellcheck uses shared writable output

- **Evidence:** `_test/shellcheck.sh` sends every scanner result to the predictable
  `/tmp/shellcheck_output.txt` path. Concurrent runs overwrite each other; an
  existing symlink can redirect writes. Failure classification also relies on
  matching lowercase severity words in human-readable output.
- **Fix:** Isolate output or remove the shared file and propagate scanner failures.
- **Breakage risk:** Low; scanner failures must cause the advertised gate to fail.
- **Validation:** Public gate tests went red then green. Scanner diagnostics now
  stream directly; no shared temporary output file is used.

### A05 — Browser startup evaluates a directory argument as shell code

- **Evidence:** `scripts/browser-tools.ts` interpolates `--profile-dir` into
  `execSync` commands for `mkdir` and `rsync`. Shell substitutions in that path
  execute despite the double quotes.
- **Fix:** Use filesystem APIs and argument-array subprocess calls.
- **Breakage risk:** Low; literal paths with spaces/metacharacters should work.
- **Validation:** A literal profile path containing a shell substitution created
  an unexpected sentinel before the fix; afterward it creates the literal
  directory and leaves the sentinel absent. Verified using a missing browser
  executable so no browser is launched.

### A10 — Tests reach real credential and host settings commands

- **Evidence:** Baseline tests in an isolated repo reached all 25 Omarchy tests
  but stalled. A real `op` daemon inherited the Bats formatter pipe: that suite
  mocked setup commands but left credential diagnostics connected to the
  installed 1Password CLI. macOS apply tests also reached the absolute
  `activateSettings` executable despite mocking other commands.
- **Fix:** Mock credential/SSH boundaries and inject the host settings activation
  command. Keep the macOS YAML fixture in a temporary checkout.
- **Breakage risk:** None to setup; these are test-only external boundaries.
- **Validation:** Baseline run stopped and its specifically identified test-created
  process cleaned up. Focused sentinel/activation regressions pass; full
  rerun passes in a snapshot of the final source.

### A11 — Bash and Zsh locale handling have drifted

- **Evidence:** Zsh checks whether the requested locale exists, but Bash still
  unconditionally exported `en_GB.UTF-8`. A public shell-config test with only
  `C`/`POSIX` available changes a valid `LANG=C` to that unavailable locale.
- **Fix:** Apply the same availability guard in Bash.
- **Breakage risk:** Low; hosts without that locale retain their inherited locale.
- **Validation:** The regression failed before the guard and passes afterward.
  This is a concrete defect caused by duplicated shell-environment behavior.

### A12 — Work configuration leaks through permissions and logs

- **Evidence:** The Git setup script set its private work include to mode 644
  and printed work email/URL rewrite contents in its success summary.
- **Fix:** Publish at mode 600, keep backups private, and report success metadata
  without dumping private config values.
- **Breakage risk:** Low; the owner can still use the include normally.
- **Validation:** A realistic work-note fixture verifies mode 600 and absence of
  confidential email and organization URL from output; red then green.

### A07 — macOS show mode exits after its first application

- **Evidence:** Under `set -e`, `((app_count++))` returns status 1 when the old
  count is zero. The read-only show command lists the first application and exits.
- **Fix:** Increment without returning a failure status.
- **Breakage risk:** None expected; show mode should complete its report.
- **Validation:** A show-mode fixture with two applications failed after the
  first before the fix and reaches the preference report afterward.

### A08 — 1Password field CSV is installed as SSH key text

- **Evidence:** `op item get --fields` returns CSV for field output. A disposable
  SSH key wrapped as that format is installed with CSV quotes; `ssh-keygen`
  rejects the private key although setup reported success.
- **Fix:** Fetch JSON and decode field/note values instead of stripping quotes
  heuristically. See the [1Password item reference](https://www.1password.dev/cli/reference/management-commands/item).
- **Breakage risk:** Low; existing notes and keys must retain their exact text.
- **Validation:** Generated disposable Ed25519 private/public keys and quoted
  SSH notes survive realistic JSON field responses unchanged. `ssh-keygen` and
  offline `ssh -G` accept them. Keys missing their required terminal newline are
  normalized; notes retain their text. Both selected-field and full-item responses
  are covered. Ambient formatting is overridden explicitly; missing `jq` fails
  before mutation. Focused safety suite passes 14/14.

### A09 — Browser profile copying deletes unrelated files

- **Evidence:** `rsync --delete` targets the user-supplied profile directory.
  A temporary destination containing an unrelated sentinel loses that file
  when the source profile lacks it.
- **Fix:** Copy without deleting destination-only files.
- **Breakage risk:** Old destination-only browser files remain until deliberately
  removed. Existing source files still refresh as before.
- **Validation:** The public CLI regression failed before removal of `--delete`
  and passes afterward; copied preferences are also verified. Browser safety
  tests pass 2/2 using disposable profiles.

### A06 — AWS runtime state belongs to a host, not a Stow tree

- **Evidence:** `aws/.aws/cli/cache/session.db` is tracked SQLite runtime state
  containing a host identifier and session metadata. The current home AWS
  directory is folded into the repo by a symlink, and repo-local ignore rules
  do not protect credentials/config/cache files. No credential fields or
  live secret keys have been established in that database.
- **Fix:** Exclude runtime caches from Stow and Git; preserve any live local state
  before removing the tracked source.
- **Breakage risk:** A current Stow symlink may point at this file, so removal
  requires checking and preserving the machine-local copy first.
- **Validation:** Public Stow tests prove AWS/GH/SSH/Nushell runtime stays local,
  ignored private files are not installed, reruns preserve local cache state,
  and an existing folded root stops before other packages change. AWS, GH, and
  Nushell were folded on this machine; the approved migration detached all three.
  SSH was already local. The setup helpers also refuse physical destinations inside
  the checkout before accessing 1Password. Public SSH examples are read directly
  from the checkout when home templates are absent. Ten privacy/config and four
  migration regressions pass, including real Stow after migration and preservation
  of newer local histories beside ignored old source histories.

## Validation and limitations

Bats suites run in an isolated snapshot of working-tree files, with temporary
homes and mocked mutation boundaries. The audit also fixed a macOS test that had
written fixtures into the real checkout. `bun audit --json`
completed successfully with `{}` (no advisories reported for the lockfile).
The first attempt failed DNS inside the network sandbox; a read-only retry
with network access succeeded. No dependencies were installed or upgraded.

Focused reproductions and final full-suite validation pass. This is a
source/config audit, not an inspection of credentials, host security, or deployed
services on every computer. The explicitly approved runtime migration is the only
live setup change applied. No package manager installation/update or host defaults
command was applied.

## Promise audit

### A13 — Security statements exceed the implementation

- **Claims:** README and AWS docs said AWS credentials never reach disk; README
  also said all sensitive data stays encrypted in 1Password, all credential
  access is logged, and MFA adds protection without specifying its boundary.
- **Evidence:** The example AWS role flow can cache temporary credentials;
  unsafe SSH mode deliberately writes private keys/backups to disk. The repo
  has no credential-access logging implementation or per-read MFA enforcement.
- **Fix:** Clarify the helper/vendor/host boundaries in README, AWS docs, and SSH
  security notes. Preserve the useful setup flows instead of prohibiting them.
- **Breakage risk:** None; documentation only. Existing dirty README harness
  edits are preserved.
- **Validation:** Changed documentation passes Markdown lint. Primary sources:
  [AWS caching](https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-files.html),
  [1Password reports](https://support.1password.com/reports/), and
  [1Password MFA](https://support.1password.com/two-factor-authentication/).

No product legal pages or external marketing promise audit applies to this
personal dotfiles repository. Vendor account plans and deployed host encryption
were not inspected; these docs now state those boundaries explicitly.

## Additional verified fixes

### A14 — AWS selects the wrong operating-system account

The helper enumerated `/Users` and chose its first directory rather than the
invoking account; on Linux that directory need not exist. It now selects
`id -un`, with `AWS_1PASSWORD_USER` for an explicit mapping. A mocked invoking
account returns the expected AWS credential-process JSON. Breakage risk: an
unintentional dependency on another user's vault item now needs an explicit
selector.

### A15 — Generated Nushell initialization captures one machine

The tracked mise activation snapshot replaced the entire PATH with personal
Mac install directories and invoked a fixed Homebrew binary. It now retains
inherited PATH and resolves mise dynamically. The public Nushell fixture
preserves its own command directory and invokes its mock mise. Breakage risk:
low; host mise must be available on PATH, as with the other shells.

### A16/A17 — Duplicate inventory parsing diverged

The system-tools report always loaded the macOS Brewfile even on Linux.
The installed-tools report's separate parser omitted the variable JetBrains
cask and tap-qualified casks, falsely labeling declared software unmanaged.
Fixes select the host manifest and use the owning Homebrew parser when present.
Breakage risk: report classifications change to match actual declarations;
these tools do not uninstall anything. Six focused manifest/system checks pass, including variable and tap-qualified
casks, conditional DSL, and Linux manifest selection.

### A18 — Local agent policy carries private state

The tracked project-local Claude permissions included private paths and broad
one-off grants for interpreters and mutations. The sanitized policy keeps bounded
repo validation/read-only lookup grants. It now lives in `.claude/settings.json`;
the tracked local-settings file is removed from the working tree and ignored for
future local approvals. Ignoring an already tracked file alone would not protect
those writes. Private path values are omitted here.

The shared-project filename and separate local-override behavior are confirmed in
[Claude Code settings documentation](https://code.claude.com/docs/en/settings).
Breakage risk: actions outside the routine scope may request normal approval;
start project sessions at the repo root to load the shared project policy.
JSON validation confirms all sanitized rule values survived the relocation;
historical copies still exist.

### A19 — Explicit 1Password skip is ignored by the Brewfile step

Bootstrap skipped its later explicit install, but the earlier Brewfile installed
both casks anyway. The explicit skip now appends both casks to Homebrew Bundle's
skip setting without discarding the caller's existing skips. The public bootstrap
regression went red then green; five existing bootstrap checks pass. Breakage
risk: none expected; explicit install and normal Brewfile policies are preserved.

### A20 — Legacy cleanup assumes ownership of any daemon at a path

Stowing macOS borders deleted any regular `n-borders-daemon` file, including an
unrelated hand-owned executable. Cleanup now requires the matching managed
LaunchAgent signature before removing a regular daemon. A public Stow fixture
preserves the unrelated file; existing managed cleanup still passes. Breakage
risk: orphaned legacy files without proof of ownership remain for manual review.

## Completed runtime migration

The user explicitly approved the live migration and source cleanup on 3 October.
`scripts/migrate-runtime-roots.sh` defaults to preview. Execute mode copies and
verifies recognized folded runtime roots, preserves private backups, and turns
known portable files into relative links GNU Stow accepts. It never changes Git
or deletes source state itself. Relative/internal nested runtime links and special
files stop before migration because copying them unchanged can change their
meaning or keep private writes routed into the checkout.

Completed on this machine:

1. Detached AWS, GitHub CLI, and Nushell runtime directories into local directories.
2. Verified all 15 backed-up regular files match the live copies byte-for-byte;
   the three live roots have mode 700. Portable file links still resolve correctly.
3. Removed only `aws/.aws/cli/cache/session.db` and `gh/.config/gh/hosts.yml` from
   the working tree, preserving live copies and backups. The index and commits
   remain untouched.
4. Verified `./stow.sh --dry-run aws gh nushell` succeeds without conflicts.

Private backups remain under
`~/.n-dotfiles-runtime-backups/<migration-id>/{aws,gh,nushell}`. Initial review
caught absolute portable links and an ineffective history ignore pattern; both
were corrected before completion. Tests exercise real GNU Stow after migration,
preview safety, cache/auth/history preservation, repeat execution, and refusal of
relative nested links. Nushell SQLite, WAL, shared-memory and text histories are
excluded from Stow even when they remain in an old source checkout.

### A21 — Prose is mistaken for a missing skill reference

The harness guide auditor interpreted ordinary `skills/docs` prose in the
existing agent guide as a missing skill path. It now identifies explicit
`SKILL.md` references. A public report fixture went red then green; the dirty
agent guide is unchanged. Breakage risk: none for documented explicit links.

### A22 — Native macOS Bash rejects empty array expansion

- **Evidence:** Expanding optional empty arrays under `set -u` crashes Bash 3.2.
  The default memory report fails without custom groups; staged shell/YAML hooks
  fail before checking for staged files; GitHub audit fails with no exclusions;
  legacy Stow cleanup fails when an owned plist/daemon exists without old symlinks.
- **Fix:** Guard empty-array expansion using syntax supported by native Bash.
- **Breakage risk:** Low; nonempty lists retain their quoted arguments.
- **Verified:** Public `/bin/bash` fixtures went red then green. GitHub calls are
  mocked with no fetching; legacy cleanup only touches temporary home fixtures.
  The platform does not declare a newer Bash as a prerequisite.

### A23 — A syntax check accepts the invalid result

- **Evidence:** `_test/nushell.bats:46` accepted both zero and one from parsing
  `config.nu`. An invalid `let =` fixture therefore passed its syntax-valid test.
- **Fix:** Require successful parsing; syntax failures now fail validation.
- **Breakage risk:** None for valid config; broken config can no longer go green.
- **Verified:** A copied public test suite with intentionally invalid config went
  green before the fix and fails afterward. The current real config parses.

### A24 — Harness audit uses an unavailable Bash builtin

- **Evidence:** `scripts/audit-harness-guides.sh:306` calls `mapfile`, absent from
  macOS Bash 3.2. Its read-only report aborts on an ordinary temporary workspace.
- **Fix:** Read lines in a portable loop and guard optional empty guide lists.
- **Breakage risk:** Low; reports retain their line-oriented path handling.
- **Verified:** Native `/bin/bash` fixtures cover guided and unguided repositories;
  the failing public report succeeds after the change.

### A25 — Documentation exposes private operational metadata

The progress record embeds a personal checkout path and per-user temporary report
path. The build-agent plan records actual host aliases, hardware/RAM, operational
roles, per-host licence allocation and personal storage placement. These are
private metadata, not credentials. The files now use portable paths and generic example roles while retaining the
design. Breakage risk: none to runtime; actual inventory stays out of public
documentation. Explicit Markdown lint passes for both files, including the
progress record normally excluded by the general lint configuration.

### A26 — PATH regression prints unquoted values

- **Evidence:** `_test/shell-configs.bats:442` prints unquoted `$PATH` and command
  output. Paths containing spaces become multiple records; the test compares the
  first truncated record and falsely reports that Arkade is not last.
- **Fix:** Quote both values in the Bash and Zsh child-shell output.
- **Breakage risk:** None to shell behavior; assertions now inspect the real PATH.
- **Verified:** The full isolated run exposed the failure. The unchanged shell
  implementation already preserved the final fallback; the existing test goes
  red then green after its output is corrected.

### A27 — Audio priorities expose device-specific identifiers

- **Evidence:** The tracked audio template contains persistent USB audio device
  identifiers and an opaque audio-device UUID. These are selection identifiers,
  not established credential values or confirmed hardware serials.
- **Fix:** Remove identifier-bearing device-list keys from the portable template.
  Omit keys rather than replacing them with empty lists, so the merge helper
  preserves existing per-machine priorities. Generic mode settings remain.
- **Breakage risk:** Existing app priorities remain. Fresh hosts configure their
  device priorities in the app or a private local config; the public template
  cannot supply this machine's device choices.
- **Verified:** The app reads its separate UserDefaults preferences, not the
  stowed source template. The mock-defaults regression went red then green: microphone, speaker, hidden
  device lists and known-device cache survive applying the portable template.
  Both audio tests and plist lint pass; no live defaults operation was performed.

## Design, duplication, and test quality

The three declarative layers remain useful boundaries: Homebrew/pacman own system
packages, Stow owns portable file links, and mise owns CLI tools/runtimes. A shared
setup framework was not justified by boilerplate alone. The audit found concrete
drift where duplicated behavior had different consequences: Brewfile parsers
(A16/A17), Bash versus Zsh locale selection (A11), and download/error handling
(A02/A08/A12). Inventory scripts now defer Brewfile parsing to its owning tool.

Existing Bats coverage is substantial, but it did not establish that development
had followed TDD. Several tests checked source text or tolerated failure rather
than exercising the promised result. New regressions use the user-approved public
boundaries and verify meaningful negative paths: failed refreshes, literal shell
paths, unrelated-file preservation, invalid config, empty native-shell lists,
private file permissions, and composed Stow/setup flows. Each production defect
was reproduced before its fix; documentation corrections use code/source evidence
and lint instead of tautological tests.

The independent second pass also found two regressions in the new SSH changes:
missing key terminal newlines and missing template fallback after excluding the
private SSH tree. Both were corrected with generated-key and fresh Stow/setup
fixtures. Migration compatibility checks similarly caught link/ignore mistakes.
Those are validation discoveries, not extra baseline findings counted above.

## Source references

Line numbers below refer to the original audited HEAD `e36f828`; fixes have moved
some lines. The finding descriptions and public regression names provide the
current review entrypoints.

| Findings | Original source reference | Regression location |
| --- | --- | --- |
| A01/A07 | `_macos/macos.sh:293`, `:102` | `_test/audit-setup-safety.bats` |
| A02/A08/A12 | `setup-ssh-from-1password.sh:295`, `:573`; `setup-gitconfig-from-1password.sh:189`, `:201` | `_test/audit-setup-safety.bats`, `_test/1password.bats` |
| A03 | `Makefile:112`, `:123`, `:161`, `:167` | `_test/audit-validation.bats` |
| A04 | `_test/shellcheck.sh:39` | `_test/audit-validation.bats` |
| A05/A09 | `scripts/browser-tools.ts:79`, `:82` | `_test/audit-browser-safety.bats` |
| A06/A20 | `stow.sh:232`, runtime Stow package roots | `_test/audit-config-privacy.bats`, `_test/audit-runtime-migration.bats` |
| A10 | `_test/bootstrap-omarchy.bats:15`; `_macos/macos.sh:220` | `_test/audit-validation.bats`, `_test/audit-setup-safety.bats` |
| A11 | `bash/.bashrc:24` | `_test/audit-shell-portability.bats` |
| A13 | README security promises; AWS/SSH security notes | Documentation lint and primary sources |
| A14 | `aws/.aws/aws-1password` account selection | `_test/audit-config-privacy.bats` |
| A15 | `nushell/Library/Application Support/nushell/vendor/autoload/mise.nu:9`, `:44` | `_test/audit-config-privacy.bats` |
| A16/A17 | `scripts/audit-system-tools.sh`; `scripts/audit-installed.sh` manifest parsing | `_test/audit-manifest.bats`, `_test/audit-system-tools.bats` |
| A18 | `.claude/settings.local.json` allow list | JSON validation and private-path scan |
| A19 | `bootstrap.sh:144` | `_test/audit-setup-safety.bats` |
| A21/A24 | `scripts/audit-harness-guides.sh:270`, `:306` | `_test/audit-validation.bats` |
| A22 | `scripts/hooks/check-staged-shell.sh:24`, YAML counterpart; `scripts/audit-github-repos.sh:441`, `:447`; `stow.sh:289`; memory group arrays | `_test/audit-validation.bats`, `_test/macos-memory-report.bats` |
| A23 | `_test/nushell.bats:46` | `_test/audit-nushell-validation.bats` |
| A25 | `.skill-loop-progress.md:3`, `:43`; `docs/plans/multi-machine-build-agents.md` | Documentation lint and metadata scan |
| A26 | `_test/shell-configs.bats:442`, `:453` | Existing PATH fallback regression |
| A27 | `audio-priority-bar/.config/audio-priority-bar/preferences.plist:15`, `:19`, `:25` | `_test/audio-priority-bar-config.bats` |

## Final verification

The first final-source run reported 244 passed, six skipped, and one failed. The
failure was A26's output quoting bug, now fixed. A fresh snapshot includes that
correction and final privacy/audio changes: **246 passed, six skipped, zero
failed**, in 157 seconds. The two browser tests skipped in the dependency-free
snapshot passed separately with existing dependencies: **248 distinct tests
verified, four existing manual/host-dependent skips remain**, across 252 tests.
The audit added 49 regression tests, including the audio preservation case.

The four remaining skips are unsafe-mode interaction, real SSH-agent socket
presence, installed-application inventory, and physical display detection. Their
existing test text says “tested manually”; this audit does not claim those manual
checks were performed. No tests were newly skipped to make the audit green.

Checks already complete:

- Full repository ShellCheck passes after all source changes.
- Browser safety tests pass 2/2 with existing Bun dependencies; the browser CLI
  builds successfully to a temporary output with 434 modules.
- Explicit lint of all changed Markdown passes, including the normally excluded
  progress record and this report.
- `make lint` reaches Markdown lint but fails on the pre-existing bare URL in the
  user's dirty `AGENTS.md:71`; `factory/.factory/AGENTS.md` is a symlink to that
  same guide, so the gate reports it twice. That user work remains unchanged.
  No lint gate was weakened to hide this existing condition.
- The final JSON policy relocation preserves the tested sanitized rule values;
  JSON validation and a focused redacted secret scan cover that final config-only
  change. All runtime code matches the tested snapshot.
- `git diff --check` passes. HEAD and the staged diff match the saved baseline
  byte-for-byte. Every original dirty/untracked path retains its saved hash except
  README's narrow security-promise corrections; its original harness section is
  separately confirmed identical.
- Approved live runtime data matches its 15 backed-up files byte-for-byte. Runtime
  roots are local mode-700 directories; subsequent Stow dry-run succeeds.

Other computers were not changed. If their runtime directories are folded into
this repo, Stow now stops before mutation; preview and review the migration there
before applying setup. No fresh Linux VM/container, remote CI job, live upgrade,
cloud-account action, or fleet-wide host-security assessment was run. Linux logic
is covered through command mocks and temporary homes, not a claim of deployment
validation on every supported platform.

The original dirty mise manifest adds a managed AI CLI although current repo
policy calls those CLIs unmanaged. It was deliberately preserved as ongoing user
work; this audit did not silently choose between that change and the policy.

## Secrets and historical privacy evidence

Installed Gitleaks 8.30.1 scanned the reviewable current tree and Git history with
redacted output. The final broad scan, before relocating the identical sanitized
JSON policy, reported:

| Scope | Scanner evidence | Result |
| --- | --- | --- |
| Tracked working files | 212 regular files copied; 1,194,552 scanner bytes | One invalid mock-key fixture hit |
| Tracked and untracked nonignored files | 227 regular files copied; 1,272,342 scanner bytes | Same invalid mock-key fixture hit |
| Default history `--all` | Scanner reports 260 commits; 3,704,308 bytes | Three old invalid mock-key fixture hits |
| Expanded history `--all --root -m` | Scanner reports 291 commits; 4,020,933 bytes | Same three fixture hits |

Git separately lists **292 reachable commits**. Scanner counters are not assumed
to equal Git's commit count. The current fixture window spans two mock private-key
markers in `_test/1password.bats`; the markers are not a usable key. No real secret
was detected in these scans; that is bounded evidence, not proof of absence.
Scanner JSON remains outside the repo with values redacted.

The tracked 20,480-byte AWS SQLite file was inspected separately: one session row
and one host-ID row, with session/host identifier and timestamp columns. No
credential columns or credential values were found in the inspected rows. A text
scanner alone cannot establish this about binary data.

Current private paths, machine inventory, agent permission state and audio-device
identifiers were cleaned up. Intentional public author/Git identity and public
signing keys remain. Historical objects still retain:

- private paths and one-off approvals in the old Claude local policy;
- personal PATH snapshots in generated Nushell initialization;
- audio-device selection identifiers;
- machine paths, hardware inventory and operational placement in the old docs;
- AWS session/host metadata, and GH CLI runtime/authentication-state structure.

Historical Silo state contains opaque runtime IDs, timestamps and preferences;
inspection found no personal identity, paths, URLs, hosts or credentials there.
Old Slicer YAML contains a local VM subnet/gateway configuration, with no
established employer infrastructure or authentication secret. Neither runtime
file exists in the current tracked tree. No credential rotation is prescribed
solely from those nonsecret identifiers.

**Historical privacy remains intentionally unresolved:** deleting working files
cannot erase existing commits, clones, forks or archives. Rewriting history would
violate the explicit commit-preservation instruction, so no rewrite, remote change
or forced push was performed. Anyone with access to older objects may retrieve
those older metadata values. Ignored live files, unreachable objects and every
computer's deployed state were not exhaustively scanned.

## Dependency advisory evidence

`bun audit --json` for `scripts/bun.lock` returned `{}`: no advisories reported.
The initial sandboxed attempt failed DNS; the approved read-only network retry
completed. There was no dependency installation or upgrade. No high/critical
lockfile CVE was established. This does not cover every installed Homebrew,
pacman, mise tool, editor plugin or independently updated AI CLI across the fleet.

## Reviewable handoff

The audit initially kept Git read-only. The user subsequently requested a branch
and PR. Audit-only changes are prepared on `codex/repository-audit-hardening`
in a separate managed checkout; the original checkout remains on `main` with its
staged and dirty work retained. Existing commits are not rewritten. The only approved live
change is the verified AWS/GH/Nushell runtime migration. Private backups remain
available at the path recorded above; audio UserDefaults were not changed.

The remaining decisions are deliberate boundaries: retain commits with historical
metadata unless a separate rewrite is requested; review/apply runtime migration
on other machines with folded roots; preserve the user's current agent-guide and
AI-CLI work rather than silently changing it for lint or policy alignment.

## PR preparation

The branch starts at the audited HEAD and contains only audit fixes. Original
agent-guide, harness, and mise changes are excluded. README contains only the
security/privacy corrections. The backup identifier is kept local; the published
report uses a generic placeholder. Earlier test totals above describe the original
combined snapshot; the isolated PR suite contains 251 tests.

PR validation also exposed test fixtures that resolved mise shims before changing
`HOME`. The Nushell and YAML fixtures now resolve installed binaries while the
real home configuration is available. Nushell syntax checks use a system-only
`PATH` to keep optional tool initialization out of those checks. The Starship
case now verifies absent and installed behavior with isolated mock executables,
including a Homebrew PATH rewrite. Both PATH-order cases share a mock mise
activation so host tool selection cannot replace their synthetic shim directories.
The full shell configuration suite passes 27/27.

The isolated PR gate passes: `make lint` and `make test`, with **247 tests passed,
four existing manual/system checks skipped, and zero failures** (251 total). Both
browser regressions are included. `MISE_AUTO_INSTALL=false` prevents optional
host tool installation during verification. Staged diff checks and the publication
privacy review pass; no actionable secret was found in staged changes. The
original checkout's HEAD, branch, index, and saved file hashes remain unchanged
through PR preparation.
