# Grimoire closes on damage — 2026-11-18

Applied player damage now closes every grimoire view, including Code Assembly and stat chants. The existing close method clears unfinished attempts without granting rewards; Tab reopens the normal contents view. Immunity-blocked hits do not interrupt. Lethal hits still enter the death context.

The cause was an explicit older exception: `GameSession.on_player_damaged()` called `world.overlay_hit()`, which restarted puzzles and chants and returned early, keeping the overlay open. Browsing already closed correctly. Removed that exception and its now-unused world/UI hooks so every mode uses the shared damage-close path. This supersedes the earlier rule that interruption regenerated a question while leaving the book open.

Validation in `evidence/grimoire-interrupt/`:

- `before.log`: reproduced assembly and chant failures for Sprite, Ghoul and Mortus damage sources.
- `actual-attacks.log`: 45 checks passed, covering the damage-source/view matrix, no interruption rewards, clean reopening, real Sprite strikes, Ghoul arrows, Mortus charges, immunity and lethal damage.
- `simulation.log`: full gameplay suite passed (914 checks).
- `git diff --check`: passed.

Run the focused regression with `godot_console --headless --path . --script res://tests/simulation/test_grimoire_interrupt.gd`.

No exported executable was rebuilt and no manual playtest was performed. Tests use isolated session state, not the player's save.
