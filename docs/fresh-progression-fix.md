# Fresh progression and collectible pages — 2026-11-18

## Report and causes

After New game (wipe progress), the grimoire exposed skills that should require discovery, while the forest contained only Quick Step, Ring of Fire and Sage Arts pickups.

The reset flow already rebuilt the grimoire from the profile correctly. The production `MetaProfile.START_PAGES` still included ten temporary spell-testing grants in addition to Scorch and Burn and Cultivate. The generator independently hard-coded three collectible IDs and validated a three-page count. Tests relied on these grants, concealing the progression defect.

## Fix

- Only Scorch and Burn and Cultivate are starter pages.
- Forest collectibles derive from the page library minus the starter list: currently 13 pickups for 15 total skills.
- Original three pages retain their preferred clearing regions. Other pages use the existing non-camp clearings, obstacle checks, 20 m page spacing, 25 m start distance and 15 m spawn-zone separation. Placement attempts increased to accommodate the additional pages without relaxing these checks.
- Generator validation requires every collectible ID. Existing pickup creation, terrain grounding, collection, Code Assembly, equip gating and persistence handle the expanded set.
- Combat/render tests explicitly grant their prerequisite skills. Production starts no longer serve as test setup.
- Existing earned saves are preserved; choosing New game deliberately resets them. Tests used a separate disposable profile, never the player's profile.
- Added missing provenance for the previously generated icon assets when content validation identified that separate ledger omission.

## Evidence

Logs and screenshots: `evidence/fresh-progression/`.

| Check | Result |
| --- | --- |
| `before.log` | Reproduced wrong starters and missing pickups on all 20 sampled seeds |
| `runtime.log` | PASS: confirmed reset button, Tab contents, saved-profile reload, all 13 actual pickup interactions, locked equip rejection, solving Firefly, and normal restart persistence |
| `simulation-final.log` | 913 checks passed |
| `content-final.log` | 201 checks passed, including 1,000 generated seeds |
| `navigation.log` | 50 checks passed, including all pages and spawn zones reachable across 20 seeds |
| `render.log` | 5 checks passed; fresh grimoire and collected/sealed Firefly screenshots inspected |
| Diff whitespace | `git diff --check` passed |

Run the dedicated regression with `godot_console --headless --path . --script res://tests/simulation/test_fresh_progression.gd`. The visual fixture is `res://tests/render/fresh_progression.tscn` (pass `-- --out=<existing evidence directory>`).

No exported executable was rebuilt. This change is verified in the Godot project; any separately exported game requires a new export. Existing imported VFX UID fallback warnings remain.
