# Performance optimization — 4 October 2026

Status: three isolated optimizations implemented and verified. The required local CI gate
runs at publication; the pull request records its final result. The invoked extreme-software-optimization skill requires
profile evidence, golden outputs, one lever per commit, and before/after metrics.

## Goal and constraints

Find material performance costs in this dotfiles repository and improve only
measured hotspots while preserving command output, exit codes, ordering, and
side effects. Work begins at audit commit `12ab8c5` in the isolated audit checkout.
The original checkout, commits, index, and existing dirty files are preserved.

- Use `hyperfine --warmup 3 --runs 10` for representative, bounded workloads.
- Record sample p50/p95/p99, serial throughput, and peak-memory evidence. Ten
  samples cannot establish production tail percentiles.
- Profile shell code with native Zsh function profiling and timed command traces.
- Capture stdout, stderr, status, and ordered side-effect traces before edits.
- Implement only a top-five measured hotspot with opportunity score at least 2.0.
- Apply one optimization lever, verify golden checksums, benchmark, and re-profile
  before selecting another. Avoid unrelated behavior or style changes.
- Use synthetic workspaces and temporary homes. No installers, login-time window
  changes, live defaults writes, machine inventory capture, or network benchmarks.
- Keep each command below the repository's five-minute approval boundary.

## Profiling plan

| Surface | Workload | Evidence | State |
| --- | --- | --- | --- |
| Shell startup | Full interactive startup and separate command mode; isolated tools/home/cache | Zsh function profile and hyperfine | Profiled |
| macOS setup | Dry-run profiles with mocked operating-system commands | Timed command trace and hyperfine | Profiled |
| Package audits | Synthetic manifests and installed/app inventory | Timed subprocess trace and hyperfine | Profiled |
| Harness-guide audit | Synthetic workspace containing varied guide files | Timed subprocess profile and golden table/TSV reports | Profiled |

Full login-shell startup invokes an asynchronous window-layout command, so it
will not be executed against the live desktop. Existing command-mode startup
checks do not represent full interactive initialization.

## Opportunity matrix

Impact × confidence ÷ effort. Estimated impact is conservative until measured
after implementation; correctness proof remains mandatory even with a high score.

| Opportunity | Impact | Confidence | Effort | Score | Decision |
| --- | ---: | ---: | ---: | ---: | --- |
| Batch three guide-file counts into one `wc` call | 4 | 5 | 1 | 20.0 | Implemented: 41.4% lower elapsed time |
| Batch Brew report membership checks | 5 | 5 | 2 | 12.5 | Implemented: 64.2% lower elapsed time |
| Batch Brew/mise intersection lookup | 3 | 5 | 1 | 15.0 | Implemented after fresh profile |
| Batch macOS YAML queries | 4 | 2 | 5 | 1.6 | Deferred: raw YAML and failure-order equivalence unproven |
| Compile large Zsh completion cache | 3 | 1 | 5 | 0.6 | Rejected: alias parsing and cache freshness change behavior |
| Batch live defaults operations | 1 | 1 | 1 | 1.0 | Deferred: mock cost does not prove native API equivalence |

## Baseline evidence

Benchmarks use synthetic inputs and installed native tools, with automatic tool
installation disabled. Package-manager and operating-system calls are mocked;
the results measure repository overhead, not real network or system-service cost.

| Workload | Samples | Mean | Sample p50 | Sample p95/p99 | Serial runs/s |
| --- | ---: | ---: | ---: | ---: | ---: |
| Harness audit: 105 directories, 244 guides | 10 | 2522.5 ms | 2511.1 ms | 2607.1 / 2607.1 ms | 0.396 |
| System audit: synthetic package/app inventory | 10 | 1541 ms | 1530 ms | 1618 / 1618 ms | 0.649 |
| Installed-package audit, narrower scope | 10 | 38.4 ms | Recorded in local JSON | Recorded in local JSON | 26.04 |
| Personal macOS dry-run profile | 10 | 968.9 ms | 962.4 ms | Recorded in local JSON | 1.032 |

Harness-audit native child maximum RSS is 2,375,680 bytes; system-audit child
maximum RSS is 2,621,440 bytes. These are peak child-process fields from Darwin
`getrusage`, not aggregate process-tree memory. Native `time -l` could not read its
clockrate sysctl in the sandbox; memory evidence uses the non-mutating fallback.

The harness audit profile launches 868 `wc` and 868 `tr` commands. The top five
command/function costs are `tr` in `count_lines` (350 calls, 590.0 ms), `wc` in
`count_lines` (350, 500.5 ms), `tr` in `count_words` (244, 384.9 ms), `tr` in
`count_bytes` (244, 384.1 ms), and `wc` in `count_words` (244, 328.6 ms). Pipeline
commands overlap: their summed durations must not be treated as wall time. The
union of `wc`/`tr` intervals is 1506.3 ms in a 3148.9 ms instrumented trace.
Profiling overhead is excluded from the Hyperfine baseline.

The system audit's trace contains 820 per-item `grep` calls. Four Brew report
loops account for 580 calls and 1018 ms of the 1870 ms instrumented trace; the
Brew/mise intersection accounts for 240 calls and 409 ms. Application metadata
queries account for 80 calls and 230 ms. The already-batched installed audit has
no equivalent measured opportunity.

The macOS personal fixture invokes `yq` 77 times; YAML work is 68.9% of its traced
time. Native operating-system timing and cross-machine speedups remain unmeasured.

Before edits, 21 harness-audit golden stdout/stderr/status files and 28 system
audit artifacts were captured. Their checksum oracles pass. macOS stdout, stderr,
status, and ordered mock-operation traces match across 24 golden artifacts.

## Changes and verification

### Round 1: batch guide counts

One `wc -l -w -c` replaces three file scans and their trimming subprocesses.
The assignment propagates a failed counter before Bash reads its three fields.
The existing largest-guide comparison and all reporting code are unchanged.

- Ordering preserved: same directory and guide iteration, same report sort.
- Tie-breaking unchanged: the original strict comparison retains the first guide.
- Floating-point: N/A; counts remain integer values from native `wc`.
- RNG seeds: N/A.
- Golden outputs: 21 stdout/stderr/status artifacts match byte for byte;
  `sha256sum -c golden_checksums.txt` passes.
- Regression tests: three public CLI tests pass before and after, including
  spaces, UTF-8, empty/unterminated files, failed counters and temporary cleanup.
- ShellCheck passes for the changed script and tests.

The interruption removed temporary evidence. It was rebuilt from the committed
baseline and candidate using 105 directories and 255 synthetic guides. Durable
local evidence now lives in ignored `_audit/performance-2026-10-04/`, including
immutable script copies, fixture, golden oracle, profiles and Hyperfine JSON.
Earlier screening numbers above are historical; this paired run is the verified
comparison used for the change.

| Metric | Before | After |
| --- | ---: | ---: |
| Mean, 10 runs after 3 warmups | 2227.4 ms | 1304.8 ms |
| Sample p50, nearest rank | 2213.3 ms | 1293.6 ms |
| Sample p95/p99, observed maximum | 2286.0 ms | 1363.6 ms |
| Serial runs/s | 0.449 | 0.766 |
| Native peak child RSS | 2,408,448 bytes | 2,408,448 bytes |
| `wc` / `tr` subprocess counts | 871 / 871 | 361 / 106 |

Elapsed time falls 41.4%, or 1.71× faster. This is synthetic local evidence,
not a promise for every machine or input. Memory is unchanged within the peak
child-process measurement; aggregate tree memory was not measured.

Fresh profile: combined `wc` (255 calls, 333 ms), skill-reference `sort`
(105, 214 ms), `sed` (105, 206 ms), `grep` (105, 194 ms), and remaining
line-count `tr` (106, 171 ms) are the top five command/function costs.
Pipeline durations overlap and must not be summed as wall time.

Reproduce from the local evidence directory:

```sh
hyperfine --shell=none --warmup 3 --runs 10 --export-json comparison.json \
  './benchmark.sh baseline' './benchmark.sh candidate'
sha256sum -c golden_checksums.txt
```

Rollback: `git revert 26fe947` on the optimization branch.

### Candidates rejected or deferred

Generic Zsh cache compilation changes alias parsing and can prefer stale compiled
files when timestamps tie; compiled file permissions also differ. The observed
29 ms opportunity does not justify an unproven behavior change. No shell startup
code was modified.

Batching macOS YAML reads must preserve raw scalar serialization, multi-document
behavior, and the timing of errors relative to prior settings operations. That
proof is incomplete, so no macOS configuration or live defaults were changed.

### Round 2: batch Brew report membership

Four ordered scans use literal string-keyed lookup tables instead of launching
one `grep` for every package. Explicit filename matching handles an empty first
file; a key prefix keeps `01` distinct from `1`. The evaluated Brewfile remains
the source of declared packages, including dynamic and tap-qualified entries.

- Ordering preserved: scan the same already-sorted input files; formula rows
  still precede cask rows in the combined missing report.
- Tie-breaking unchanged: normalization and duplicate removal are untouched.
- Floating-point: N/A; package names remain strings.
- RNG seeds: N/A.
- Golden outputs: all 23 durable report/stdout/stderr/status/ordered mock-command
  artifacts match byte for byte; their SHA-256 oracle passes.
- Two new public CLI tests pass against baseline and candidate, covering empty
  lookup files, literal punctuation, numeric-looking names, and output order.
- Six existing system/manifest tests and ShellCheck pass.

The rebuilt synthetic fixture has 240 installed formulae/leaves, 200 declared
formulae, 80 installed casks, 60 declared casks, and 160 mise keys. Applications
and PATH inventories are empty; native package managers are mocked. The profile
confirms 580 Brew-report `grep` calls consuming 867 ms and 240 intersection
calls consuming 369 ms. This is repository overhead, not installed-tool latency.

| Metric | Before | After |
| --- | ---: | ---: |
| Mean, 10 runs after 3 warmups | 1205.7 ms | 432.1 ms |
| Sample p50, nearest rank | 1195.7 ms | 427.8 ms |
| Sample p95/p99, observed maximum | 1302.7 ms | 459.9 ms |
| Serial runs/s | 0.829 | 2.314 |
| Native peak child RSS | 2,506,752 bytes | 2,523,136 bytes |

Elapsed time falls 64.2%, or 2.79× faster. The small child RSS increase is
16 KiB; no aggregate process-tree memory conclusion is drawn.
Fresh top five costs: intersection `grep` (240 calls, 336 ms), summary `wc`
(7, 8.3 ms), report `sed` (5, 6.7 ms), batched difference `awk` (4, 6.6 ms),
and formula-manifest `sort` (1, 5.0 ms). The intersection is now the dominant
measured opportunity and remains a separate lever.

Durable local evidence: `_audit/performance-2026-10-04/system/` contains the
fixture, immutable source copies, golden reports/oracle, verifier and paired
benchmark JSON. The same Hyperfine and checksum commands from Round 1 apply.
Rollback: `git revert 40e38dd` on the optimization branch.

### Round 3: batch Brew/mise intersection

One string-keyed ordered scan replaces 240 per-formula `grep` calls. It uses
explicit filename matching and prefixed keys, as the previous difference scan
does, while preserving the intersection predicate and existing report message.

- Ordering preserved: scan installed formulae in their existing sorted order.
- Tie-breaking unchanged: normalization, mise parsing and deduplication untouched.
- Floating-point: N/A; names are strings, including numeric-looking names.
- RNG seeds: N/A.
- Golden outputs: the same 23 artifacts and checksum oracle pass after both
  package changes, including every generated report and ordered mock calls.
- The overlap regression passes before and after, including `01` versus `1`,
  literal dots and empty mise declarations. All three new system tests pass.
- ShellCheck and the optimization diff's whitespace checks pass.

| Metric | After Round 2 | After Round 3 |
| --- | ---: | ---: |
| Mean, 10 runs after 3 warmups | 449.6 ms | 88.7 ms |
| Sample p50, nearest rank | 448.6 ms | 87.5 ms |
| Sample p95/p99, observed maximum | 453.4 ms | 97.8 ms |
| Serial runs/s | 2.224 | 11.279 |
| Native peak child RSS | 2,523,136 bytes | 2,441,216 bytes |

The separate intersection lever cuts elapsed time 80.3%, or 5.07× faster.
A final baseline-versus-final paired run measures the combined package change:
1197.0 ms to 80.0 ms, 93.3% lower elapsed time, or 14.96× faster. Its sample
p50 is 1190.8/80.1 ms, p95/p99 maximum is 1232.4/81.4 ms, and serial throughput
is 0.835/12.501 runs/s. Differences between paired runs reflect local timing
variation; the ratios are each computed within their respective run.

Fresh final top five command/function costs are summary `wc` (7 calls, 8.2 ms),
report `sed` (5, 6.5 ms), difference `awk` (4, 6.2 ms), inventory `sort`
(3, 4.4 ms), and formula-manifest `sort` (1, 4.3 ms). No per-item membership
`grep` remains. Further consolidation offers small gains and requires broader
behavior proofs; it is deferred rather than mixed into these three levers.

The final source copy, profile and paired JSON are retained beside the preceding
rounds in the ignored local evidence directory. For the combined comparison use
`./benchmark.sh baseline` and `./benchmark.sh final` with the Round 1 flags.
Rollback: `git revert 655ca92` on the optimization branch.

## Final review and limits

Adversarial review of every changed runtime line found no actionable regression.
Removed counter helpers have no remaining call sites. Empty inputs, exact string
membership, deterministic row order, native Bash compatibility and counter
failure propagation were checked against the baseline and regression tests.

This work adds no dependencies and does not modify live configuration. The
accepted changes optimize audit commands. Shell compilation was rejected;
macOS YAML batching was downgraded below the implementation threshold because
serialization and failure timing remain unproven. Remaining guide pipeline
costs require a separate parser-equivalence proof before consolidation.

Each runtime lever is independently committed. Revert in reverse order when
rolling back all optimizations. The audit hardening commit remains separate.

Publication target: [pull request #124](https://github.com/nickromney/n-dotfiles/pull/124)
on `codex/repository-audit-hardening`. The six new boundary regressions supplement
the original audit tests. Pre-commit ShellCheck, Markdown formatting, whitespace
and redacted staged-secret checks pass for each optimization commit.

Commits use the previously established per-command unsigned fallback because
1Password signing was unavailable. No Git signing configuration was changed.
