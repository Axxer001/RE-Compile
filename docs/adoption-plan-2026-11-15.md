# Adoption Plan

> **Generated**: 2026-11-15
> **Project phase**: Production (observed; configured stage Concept, not advanced at `minimal`)
> **Engine**: Godot 4.7 (GDScript, Forward+)
> **Template version**: v1.0+ (kit 1.3.0)

Work through these steps in order. Check off each item as you complete it.
Re-run `/adopt` anytime to check remaining gaps.

---

## Step 1: Fix Blocking Gaps

None. The v1.0 migration check found nothing to migrate: `project.yaml` exists and the legacy files agree with it.

---

## Step 2: Fix High-Priority Gaps

### No game brief
`design/game-brief.md` is absent, so the one `minimal`-tier format check has nothing to audit and `/create-stories` has no Features list to read. `docs/design-brief.md` is the superseded salvage-horror pitch and stays as history.
**Fix**: `/reverse-document design scripts` (writes the brief from the built game; take the pitch and pillars from `docs/pivot-grimoire-plan.md`).
**Time**: 1 session
- [ ] `design/game-brief.md` written

---

## Step 3: Bootstrap Infrastructure

Not on the minimal path: the brief's build order is the plan. Next: `/create-stories` (no stories exist yet), or `/dev-story` once stories exist.

---

## Step 4: Medium-Priority Gaps

### `naming.*` not set in `project.yaml`
**Fix**: `/project-settings naming.<key>=<value>` (GDScript: snake_case files and variables, PascalCase classes).
**Time**: 5 min
- [ ] naming conventions recorded

### `performance.*` not set in `project.yaml`
The project has a real budget: 7.7 ms p95 frame time on the real clock (`tests/performance`).
**Fix**: record it with `/project-settings`.
**Time**: 5 min
- [ ] performance budget recorded

---

## Step 5: Optional Improvements

None.

---

## What to Expect from Existing Stories

No stories exist. Existing stories, when there are some, continue to work with all template skills. New format checks (TR-ID validation, manifest version staleness) auto-pass when the fields are absent. Do not regenerate stories that are in progress or done.

---

## Re-run

Run `/adopt` again after Step 2 to verify the HIGH gap is resolved.

Review mode resolves to `solo` (from `modes.rigor: minimal`); nothing here pins it.
