# n-dotfiles

This context names the concepts used to manage public, private, and agent-visible automation assets in this dotfiles repository.

## Language

**Skill Catalog**:
The curated set of skills that should be available for agent use on this machine.
_Avoid_: skill pile, installed skills

**Agent Harness**:
An LLM coding environment such as Claude Code, Codex, OpenCode, or a related desktop wrapper.
_Avoid_: coding agent, tool, client

**Harness Asset**:
A durable configuration artifact used by an **Agent Harness**, such as a skill, agent, MCP server declaration, plugin, hook, rule, or setting.
_Avoid_: skill, agent stuff, config file

**Asset Catalog**:
The curated set of **Harness Assets** that should be available on this machine.
_Avoid_: skill catalog, Chops library

**Harness Repository**:
A repository that stores portable **Harness Assets** and the rules for exposing them to **Agent Harnesses**.
_Avoid_: agents repo, skills repo

**Private Harness Repository**:
A separate non-public **Harness Repository** for paid, private, or personal-only **Harness Assets**.
_Avoid_: private skills folder, secret dotfiles

**Optional Private Source**:
A **Private Harness Repository** that is used only when present and skipped without error when absent.
_Avoid_: required private checkout, missing dependency

**Shared Asset Source**:
A top-level area in a **Harness Repository** for **Harness Assets** that are intended to be reused across harnesses.
_Avoid_: shared folder, global copy

**Harness View**:
The harness-specific layout that an **Agent Harness** or Chops scans.
_Avoid_: generated copy, installed folder

**Chops View**:
The catalog Chops displays by reading assets exposed through **Harness Views**.
_Avoid_: Chops source, Chops database

**Runtime State**:
Ephemeral or machine-local data created while an **Agent Harness** runs.
_Avoid_: config, setup

**Visible Skill Root**:
A directory scanned by an app or agent to discover available skills.
_Avoid_: skills folder, install location

**Global Skill Root**:
The Chops-visible skill root currently represented by `~/.agents/skills`.
_Avoid_: global skills, dot agents

**Shared Skill Root**:
The single **Visible Skill Root** used for skills that should be available across agents.
_Avoid_: common skills folder, global skills folder

**Agent-Specific Skill Root**:
A **Visible Skill Root** reserved for skills that genuinely need to differ for a specific agent.
_Avoid_: duplicate agent folder, per-tool copy

**Duplicate Skill**:
The same skill content exposed from more than one **Visible Skill Root**.
_Avoid_: duplicate directory, duplicate version

**Skill Drift**:
The same skill name resolving to different content in different **Visible Skill Roots**.
_Avoid_: duplicate, fork

**Skill Reset**:
A deliberate one-time replacement of existing installed skills with a smaller curated set from known sources.
_Avoid_: dedupe, cleanup

**Symlink Route**:
The path by which a **Harness View** exposes a source **Harness Asset** to an **Agent Harness**.
_Avoid_: copy, install path

**Discovery Route**:
The path or configured location an **Agent Harness** or Chops scans to find **Harness Assets**.
_Avoid_: symlink route, folder layout

**Placeholder Asset**:
An empty or inert file at a known harness path that should not be treated as meaningful configuration.
_Avoid_: config, rule, instruction

**Project Harness Guide**:
A repository-local instruction file such as `AGENTS.md` or `CLAUDE.md` that tells harnesses how to work in that project.
_Avoid_: global instruction, harness asset

**Workspace Harness Audit**:
A read-only scan across local repositories that reports **Project Harness Guides** and their references to repo-local skills.
_Avoid_: installer, migration, reset

**Bloated Harness Guide**:
A long `AGENTS.md`, `CLAUDE.md`, or equivalent **Project Harness Guide** that may contain copied guidance better kept in repo-local skills or docs.
_Avoid_: legacy Claude guide, canonical guide

## Relationships

- A **Skill Catalog** is exposed through one or more **Visible Skill Roots**.
- An **Asset Catalog** contains one or more kinds of **Harness Assets**.
- A **Harness Repository** contains a **Shared Asset Source** and zero or more **Harness Views**.
- An **Optional Private Source** contributes private **Harness Assets** without being required for public setup.
- An **Agent Harness** uses **Harness Assets** and produces **Runtime State**.
- A **Chops View** reflects **Harness Views** and should not introduce its own source layout.
- A **Shared Skill Root** is the default home for cross-agent skills.
- The **Global Skill Root** is a candidate implementation of the **Shared Skill Root**.
- An **Agent-Specific Skill Root** is an exception for skills that differ by agent.
- A **Duplicate Skill** can exist even when copied files are byte-for-byte identical.
- **Skill Drift** is distinct from a **Duplicate Skill** and must be resolved deliberately.
- A **Skill Reset** avoids preserving accidental historical installs as part of the new catalog.
- A **Symlink Route** should make the source of each exposed asset clear without copying private content.
- A **Discovery Route** is a harness behavior and should be understood before choosing a **Symlink Route**.
- A **Placeholder Asset** may indicate a possible **Discovery Route** but is not part of the curated catalog until it has content.
- A **Project Harness Guide** can reference repo-local skills without making those skills part of the global **Asset Catalog**.
- A **Workspace Harness Audit** belongs with other local repo audits and should not mutate harness configuration.
- A **Bloated Harness Guide** is a review signal because it may duplicate guidance that belongs in repo-local skills or docs.

## Example dialogue

> **Dev:** "Chops shows `changelog-md-workmanship` under both Claude and Codex. Is that two versions?"
> **Domain expert:** "No, that is a **Duplicate Skill** because the same skill is visible from two **Visible Skill Roots**."

> **Dev:** "Where should `changelog-md-workmanship` live if both Claude and Codex can use it?"
> **Domain expert:** "In the **Shared Skill Root**, unless one agent needs a materially different version."

> **Dev:** "What if `grill-with-docs` has different content under Global and Codex?"
> **Domain expert:** "That is **Skill Drift**, not a harmless **Duplicate Skill**."

> **Dev:** "Should setup infer the correct catalog by deduplicating every old skill?"
> **Domain expert:** "No. A **Skill Reset** starts from known sources and only re-adds selected skills."

> **Dev:** "Do we need backups before rebuilding installed skill roots?"
> **Domain expert:** "No. The sources are version controlled; the important part is clear **Symlink Routes**."

> **Dev:** "Should we decide whole-directory symlinks before checking harness settings?"
> **Domain expert:** "No. First identify the **Discovery Routes**; then choose the simplest **Symlink Routes** that do not duplicate them."

> **Dev:** "`~/.codex/AGENTS.md` exists but is empty. Is that a managed rule?"
> **Domain expert:** "No. It is a **Placeholder Asset** unless we intentionally put global Codex instructions there."

> **Dev:** "A repo has `AGENTS.md` pointing at `skills/use-platform/SKILL.md`. Is that a global skill?"
> **Domain expert:** "No. That is a **Project Harness Guide** referencing a repo-local skill."

> **Dev:** "Should we audit all personal repos for `CLAUDE.md`, `AGENTS.md`, and skill references?"
> **Domain expert:** "Yes. That is a **Workspace Harness Audit**, not an install or reset step."

> **Dev:** "Is a `CLAUDE.md` or `AGENTS.md` file automatically healthy project guidance?"
> **Domain expert:** "No. Treat long guide files as possible **Bloated Harness Guides** until they are shown to delegate cleanly."

> **Dev:** "Should logs and session databases go in dotfiles with MCP settings?"
> **Domain expert:** "No. MCP settings are **Harness Assets**; logs and sessions are **Runtime State**."

> **Dev:** "Chops shows Skills, Agents, and Rules. Are we only managing skills?"
> **Domain expert:** "No. Skills are one kind of **Harness Asset** in the broader **Asset Catalog**."

> **Dev:** "Should `shared/` be scanned directly by agents?"
> **Domain expert:** "No. `shared/` is the **Shared Asset Source**; agents and Chops should scan **Harness Views**."

> **Dev:** "What if private paid skills are not cloned on a new machine?"
> **Domain expert:** "The **Optional Private Source** is skipped without error, so those skills are simply unavailable."

> **Dev:** "Should Chops scan source folders like `shared/`?"
> **Domain expert:** "No. The **Chops View** should reflect the same **Harness Views** exposed to Claude, Codex, and other harnesses."

## Flagged ambiguities

- "No duplication" means eliminating duplicate visible skills, not only deleting duplicate tracked files from the repository.
