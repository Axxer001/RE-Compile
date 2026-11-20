# RE:Compile -- Claude Code Game Studios

RE:Compile (Godot 4.7, GDScript): a first-person spellcasting action RPG that
teaches beginner C++ through its Grimoire pages. Managed with the Claude Code
Game Studios kit (v1.3.0, MIT, added 2026-11-15): 49 coordinated subagents.
Each agent owns a specific domain, enforcing separation of concerns and quality.

## Technology Stack

- **Engine**: Godot 4.7 (Forward+)
- **Language**: GDScript (the in-game lessons and puzzle programs are C++, checked with g++)
- **Version Control**: Git; `main` on GitHub (Axxer001/RE-Compile)
- **Build System**: Godot export, preset "Windows Desktop (encrypted)" -> `../RECompile-FPS-build/RECompile.exe`
- **Asset Pipeline**: Godot import; licensed assets ledgered in `docs/asset-licenses.md`

> **Note**: Engine-specialist agents exist for Godot, Unity, and Unreal with
> dedicated sub-specialists. Use the set matching your engine.

## Project Structure

@.claude/docs/directory-structure.md

## Engine Version Reference

<!-- ENGINE-REFERENCE-IMPORT: the line under this comment is engine-specific,
     and there is none until an engine is set. /setup-engine, the grow's record
     step and /project-settings (engine.name) write
     @docs/engine-reference/<engine>/VERSION.md here for the chosen engine. Skills
     that need the pinned version read that file on demand either way. -->
@docs/engine-reference/godot/VERSION.md


## Technical Preferences

`project.yaml` at the repo root is the primary config store — engine, specialists,
naming, platform, performance, modes. Skills resolve it via `resolve_config`
(see `.claude/docs/config-resolution.md`).

`.claude/docs/technical-preferences.md` is the **legacy fallback**, read on demand
when a key is absent from `project.yaml`. It is not imported here: before
`/setup-engine` runs it is almost entirely `[TO BE CONFIGURED]` placeholders, and
after it runs `project.yaml` holds the real values.

## Coordination Rules

@.claude/docs/coordination-rules.md

## Collaboration Protocol

**User-driven collaboration, not autonomous execution.**
Every task follows: **Question -> Options -> Decision -> Draft -> Approval**

- Agents MUST ask "May I write this to [filepath]?" before using Write/Edit tools
  (exempt: `active.md` appends, agent memory, a subagent's new file at the path
  its orchestrating skill named; see `.claude/rules/agent-memory.md`)
- Agents MUST show drafts or summaries before requesting approval
- Multi-file changes require explicit approval for the full changeset
- No commits without user instruction
- A skipped or dismissed question is not an answer: act on nothing, re-ask in
  plain text and wait
- Started outside this file's folder? Warn first: hooks, deny rules and the
  ask-first mode load only when Claude Code starts here

See `docs/COLLABORATIVE-DESIGN-PRINCIPLE.md` for full protocol and examples.

> **First session?** Say "make me a game" (`/prototype`), or run `/start` to begin
> the guided onboarding flow.

## Coding Standards

@.claude/docs/coding-standards.md

## Context Management

Read `.claude/docs/context-management.md` on demand — it is a reference, not
session context. Two of its conventions are load-bearing and cited by name
elsewhere in the repo, so they are restated here rather than lost:

- **`production/session-state/active.md` is the session checkpoint.** The file is
  the memory, not the conversation. Read it first after any compaction, crash, or
  `/clear`.
- **Helpers in `.claude/scripts/` emit observations, never verdicts.** A script
  that scores or judges will eventually contradict a mode or override it cannot
  see. (Cited by `artifact-check.sh` and `adr-dep-graph.sh`.)

## RE:Compile project rules

- **Code and tests**: game code in `scripts/` (`engine.code_root`), scenes in
  `scenes/`, tests in `tests/` (simulation, render, playthrough, performance
  runners; not gdUnit4). The gate is `verify.ps1`, one suite per call:
  `powershell.exe -NoProfile -ExecutionPolicy Bypass -File ./verify.ps1 -Suite <Content|Simulation|Render|Mobile|Playthrough|Performance>`.
  A runner that hits a SCRIPT ERROR can still print RESULT PASS: check its log.
- **Puzzle bank**: `python tools/make_code_assembly_bank.py data/puzzles/code_assembly.json`
  (every program compiled with `g++ -std=c++17 -fsyntax-only -Wall -Werror`).
- **Secrets**: the PCK encryption key (`.godot/export_credentials.cfg`,
  `~/.config/recompile/pck_key.txt`) is never committed or printed.
- **Commits to main** start with the update type: `[Feature]`, `[Bug fix]`,
  `[Content]`, `[Settings]`, `[Performance]`, with an "Update type:" line in the body.
- **Shared checkout**: other sessions may work in this folder on their own
  branch. Check `git branch --show-current` and stage only your own files.
- **Plans** live in `docs/` (`plan-*.md`, `pivot-grimoire-plan.md`).
