# Story 001: Ranks C to S

> **Epic**: RE:Compile
> **Status**: Ready
> **Layer**: Feature
> **Type**: Logic
> **Estimate**: M
> **Manifest Version**: N/A (minimal — no control manifest)
> **Last Updated**: [set by /dev-story when implementation begins]

## Context

**GDD**: `design/game-brief.md`
**Requirement**: Brief MVP feature 8 (Ranks C to S)

**ADR Governing Implementation**: N/A (minimal — no ADRs)
**ADR Decision Summary**: N/A (minimal — no ADRs)
**ADR Version**: N/A (minimal — no ADRs)

**Engine**: Godot 4.7 | **Risk**: HIGH (4.7 timeline row in `docs/engine-reference/godot/VERSION.md`)
**Engine Notes**: none (no ADR engine-compatibility analysis at minimal)

**Control Manifest Rules (this layer)**: N/A (minimal — no control manifest)

---

## Acceptance Criteria

*From the brief's Goal & fail state and Features item 8, scoped to this story:*

- [ ] Each of ranks C, B, A and S has a promotion mission the player can see in the mission tracker.
- [ ] Completing the current rank's mission promotes the player one rank, with the rank-up banner and its stat points.
- [ ] A run's promotions persist across death, as rank does today (pages and rank kept).
- [ ] Pages that need a higher rank become equippable once that rank is reached.
- [ ] Rank S is the top: no further mission shows, and nothing breaks past it.

Open question (not stated in the brief): the mission target for each of C, B, A and S. *INTENT UNKNOWN — set when built; ask Sir before choosing values.*

---

## Implementation Notes

- Today `scripts/core/progression.gd` has `RANK_MISSIONS := {"E": {"kills": 20}}`; promotion runs in `_check_rank()`, points via `points_for_rank()`.
- Rank persistence lives in `scripts/core/meta_profile.gd` (`rank`, `set_rank`).
- Keep mission targets data-driven (one table), per the coding standards.

---

## Out of Scope

- Rank-gated new content (new pages for C to S): not in this story.

---

## Files

- `scripts/core/progression.gd`
- `scripts/core/meta_profile.gd`
- `tests/simulation/test_ranks.gd` (planned; RE:Compile's runners live in `tests/simulation/`)

---

## QA Test Cases

*N/A — no qa-lead specs at this tier; implement against the Acceptance Criteria above.*

---

## Test Evidence

*At `qa.level: minimal` tests are waived (advisory).*

**Story Type**: Logic
**Required evidence**: Test: waived at qa.level minimal (a simulation check in `tests/simulation/` is still the project's practice).

**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: None
- Unlocks: None
