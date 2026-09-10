# macOS memory baseline

This document records the measurement method and adoption decisions from the
omacosy comparison. Measurements are workload-specific snapshots, not product
benchmarks. Repeat them after upgrades and while exercising the feature being
evaluated.

## Measurement method

Use physical footprint as the primary comparison. RSS is useful for diagnosis,
but it counts shared framework pages in every process. Always group the main
process with its helpers.

```bash
make memory-report
./scripts/macos-memory-report.sh --count 12 --interval 300
./scripts/macos-memory-report.sh --format tsv > /tmp/mac-memory.tsv
```

The sampler is read-only. `Peak sum MiB` is an upper bound because individual
processes may have reached their lifetime peaks at different times.

For an application comparison:

1. Start from the same open documents, tabs, or project.
2. Let startup activity settle.
3. Record an idle sample.
4. Perform the same representative task in each application.
5. Record immediately after the task and again five minutes later.
6. Prefer a plateau over a one-shot low number.

## Baseline

Snapshot taken on 2026-08-25 on a 16 GiB Mac with mixed everyday workloads.
The system compressor held 6.1 GiB, so memory contention was already material.
The in-tree `n-borders` implementation described by this historical snapshot
has since moved to the standalone sibling `Borders` project; the old name is
retained below only to keep the recorded measurements accurate.

| Process family | Processes | Physical footprint | Interpretation |
|---|---:|---:|---|
| Brave | 29 | 3,002 MiB | Largest interactive target; workload was much heavier than Chrome |
| RubyMine | 3 | 2,731 MiB | Large native/JVM allocation beyond its 724 MiB live Java heap |
| Wispr Flow | 12 | 1,031 MiB | Electron family; repeated idle samples stayed near 1 GiB |
| Google Chrome | 10 | 480 MiB | Not comparable until it runs the same tabs and extensions as Brave |
| Docker Desktop | 10 | 340 MiB | Idle physical footprint; VM is configured with a 9 GiB memory ceiling |
| JankyBorders | 2 | 129 MiB | Replaced by the focused-window backend below |
| Spokenly | 1 | 96 MiB | About one tenth of Wispr Flow before an active-dictation comparison |
| Chops | 1 | 84 MiB | Modest and stable during the sample |
| Ghostty | 2 | 168 MiB | Later post-reboot UI sample; includes two windows/processes |
| Clearly | 4 | 67 MiB | Included three Sparkle updater helpers active during the sample |
| Bloom | 1 | 61 MiB | Modest and stable during the sample |
| Bartender | 2 | 34 MiB | Small relative to the applications it manages |
| Homerow | 1 | 31 MiB | Small and stable enough to keep |
| AeroSpace | 1 | 25 MiB | Matches omacosy's measurement closely |
| Superkey | 1 | 20 MiB | Small and avoids a Karabiner dependency |
| AudioPriorityBar | 1 | 15 MiB | Native, event-driven, and already cheaper than a general bar |
| Pearcleaner sentinel | 1 | 2 MiB | Main UI was closed; resident monitoring cost is negligible |
| Silo UI + session host | 2 | 31 MiB | Later post-reboot idle UI sample with writing-tools and terminal open |

These four utilities are not meaningful memory-pressure targets compared with
Brave, RubyMine, or Wispr Flow.

### Post-reboot follow-up

On 2026-08-26, after rebooting and lowering Docker Desktop's allocation, a
fresh snapshot showed Brave at 2,521 MiB, Docker Desktop at 342 MiB, and
`n-borders` at 11 MiB. The system still reported 6.1 GiB in the compressor,
so Brave remains the dominant interactive pressure source. Silo was not
running in that initial snapshot, and Brave still had no `TotalMemoryLimitMb`
policy configured.

A later three-sample active snapshot put Brave between 2,945 and 3,116 MiB,
with CPU ranging from 1% to 30%, while Silo stayed at 31 MiB and Ghostty at
109 MiB. The browser's transient growth and CPU spikes reinforce its priority
as the next trial target.

CodexBar was removed after measuring about 866 MiB of physical footprint and a
peak near 1 GiB. Its package and Homebrew tap were removed; user data was kept
so the uninstall remained reversible.

## Decisions

| omacosy idea | Decision | Evidence / boundary |
|---|---|---|
| Physical-footprint process-family profiling | Adopt | `scripts/macos-memory-report.sh`; physical footprint is primary, RSS is diagnostic |
| Single native focused-window border daemon | Adopt | The former `n-borders` implementation is ~11 MiB versus JankyBorders at ~129 MiB |
| Native publisher-driven bar model | Borrow selectively | Apply the event-driven, warm-model, off-main-thread design to AudioPriorityBar and future bar work |
| Karabiner Super/Omarchy bindings | Reject | Superkey + Homerow are ~58 MiB in the latest sample and preserve the existing AeroSpace model |
| Omarchy package/bootstrap layer | Reject | This repository's macOS Brewfile/Stow/mise layers already own the machine |
| Whole omacosy bar replacement | Defer | Bartender + AudioPriorityBar are not a measured pressure source; replace only for a demonstrated workflow/latency gain |

### Keep the input stack

Keep Superkey and Homerow. Together they use about 58 MiB in the latest sample.
omacosy reports
about 24 MiB for four Karabiner processes, but saving roughly 27 MiB does not
justify returning to Karabiner solely for a Super key.

### Keep AeroSpace

AeroSpace uses about 25 MiB and is not a meaningful pressure source. The local
bindings and workspace model should remain; omacosy's Karabiner and Omarchy
bindings do not need to be adopted.

### Adopt the focused-window border backend

The installed JankyBorders family measured about 129 MiB. The former adapted
`n-borders` daemon measured 10.3 MiB across three post-reboot samples. It draws
one click-through `CAShapeLayer` ring for the focused window rather than
retaining a bitmap per window, recovering roughly 119 MiB on this machine.

The tradeoff is real: the implementation uses private SkyLight APIs and shows
only the focused-window ring. The ring is deliberately opaque bright yellow
(`0xfff5f543`) and 8 points wide, preserving the high-contrast visual cue used
for colour-blind accessibility. `n-borders off` restores JankyBorders when it
is present before unloading the native daemon; otherwise it leaves both
backends stopped. `n-borders on` reverses that order. The source
is MIT licensed in [paulsp94/omacosy](https://github.com/paulsp94/omacosy).

The live off/on cycle was exercised after activation. The daemon log recorded
focused-window show events and SkyLight callbacks, with no fallback-to-polling
error. The old `borders` binary is still installed on this machine but is no
longer in the Brewfile or its tap; purging that existing formula is a separate
destructive machine action and has not been performed.

### Borrow the bar architecture, not the whole bar

omacosy's bar reports a 32 MiB footprint. AudioPriorityBar and Bartender total
about 49 MiB, but they do not provide equivalent functionality. Replacing both
would save little compared with the browser, IDE, or dictation application.

Adopt these design rules in future menu-bar work:

- subscribe to native publishers instead of polling;
- keep a warm in-memory model and render from it;
- move CLI and accessibility queries off the main thread;
- create popup views when opened and release them when closed;
- log event-to-render latency so perceived jank is measurable.

AudioPriorityBar already follows the most important rule through CoreAudio
listeners. Before comparing release builds, normalize its installed bundle ID:
the current app identifies as a test host while its launchd configuration uses
the release identifier.

### Prefer Spokenly on memory, pending a dictation test

Spokenly held at 96 MiB over three idle samples. Wispr Flow ranged from 948 to
1,049 MiB and used 5–15% CPU during the same interval. Spokenly is the default
memory choice unless a same-script dictation test demonstrates a substantial
quality or workflow advantage for Wispr Flow.

### Put a soft ceiling on Brave before changing browsers

Mainstream browsers do not provide a strict resident-memory ceiling. Chromium
does provide the enterprise policy
[`TotalMemoryLimitMb`](https://chromeenterprise.google/policies/total-memory-limit-mb/),
which starts discarding tabs after the browser exceeds the configured amount.
It is a soft threshold, so active work can exceed it. Brave states that it
supports Chromium policies on macOS.

A 2 GiB trial is proportionate for this 16 GiB machine:

```bash
./scripts/configure-brave-memory.sh on --limit 2048
```

Restart Brave and confirm the policy in `brave://policy`. To undo the trial:

```bash
./scripts/configure-brave-memory.sh off
```

The repository helper is opt-in and leaves the current policy unchanged until
the trial is explicitly requested.

Do not compare Brave and Chrome until both run the same tab set, profiles, and
extensions. The current 3,002 MiB versus 480 MiB snapshot does not meet that
standard.

### Silo is promising on memory, but the workload comparison is not complete

After reboot, Silo 0.52.0's actual desktop UI plus session host settled at
31 MiB physical footprint (RSS 77 MiB) with the `writing-tools` workspace and
integrated terminal open. In a three-sample trial two seconds apart, Silo
remained at 31 MiB while Ghostty remained at 109 MiB with two processes. This
is an idle terminal/editor comparison, not a full coding benchmark, but it is
stable evidence of roughly a 78 MiB resident-memory advantage for Silo before
language-server or build workloads are added. The same project, files,
terminal commands, and RubyMine workflow still need to be exercised side by
side.

That distinction matches [Silo's own project description](https://github.com/silo-code/silo):
terminals and coding agents are its primary surface, with the editor sharing
the workspace rather than replacing a full IDE. Treat it as a strong Ghostty
and agent-workspace candidate, not an automatic RubyMine replacement.

## Adoption order

1. Run the Spokenly versus Wispr Flow active-dictation comparison.
2. Trial Brave's 2 GiB soft policy and measure tab reload friction.
3. Compare active Silo with Ghostty and RubyMine on the same project.
4. Revisit custom bar work only for workflow or latency improvements, not RAM.
