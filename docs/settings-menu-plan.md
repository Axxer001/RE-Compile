# Settings menu plan: keybinds + mouse sensitivity (hip and ADS)

Status: plan, 2026-11-10. Part of rehaul §4.8 (Esc menu → Settings).

## Current state
- Sensitivity is a hard-coded constant: `fps_controller.gd` `MOUSE_SENSITIVITY := 0.12` (degrees per pixel), with no ADS variant.
- 19 input actions are defined in `project.godot` (move_*, sprint, crouch, jump, attack, aim, reload, throw, cycle_throwable, bullet_time, flashlight, inventory, interact, drop, pause, confirm), plus `slot_1..4` in `input_router.gd`.
- There's no pause menu UI yet. The Esc `"pause"` action already flows through `input_router.gd` → `GameSession.paused()`.

## Scope (simple, MVP)
1. **Esc → pause menu:** Resume / Settings / Restart / Quit.
2. **Settings → Controls tab:**
   - Hip sensitivity: slider 0.01–1.00 °/px, default 0.12, plus a numeric field.
   - **ADS sensitivity:** a multiplier on hip, 0.10–2.00, default 0.80. Optionally scale by the FOV ratio, as Apex does.
   - Invert Y (toggle).
   - Sprint mode: Toggle / Hold (`movement_tuning.sprint_toggle` already exists).
   - **Keybind list:** one row per action with primary and secondary binding.
     - Click a binding, then press a key or mouse button to rebind.
     - Esc cancels a rebind; Backspace clears the binding.
     - Conflicts are shown inline ("Already bound to Jump: swap?").
   - "Reset to defaults" button.
3. Settings apply live and are saved to `user://settings.cfg`, then loaded at startup.

## Architecture

| File | Role |
|---|---|
| `scripts/core/settings.gd` (new, `RefCounted`, owned by `GameSession` like `TimeService`) | Holds values, `load()` / `save()` to `ConfigFile`, `apply_bindings()` to `InputMap`, emits a `changed` signal. Pure data, testable headless |
| `scripts/ui/pause_menu.gd` (new) | Esc overlay; pauses via the existing `GameSession` pause path |
| `scripts/ui/settings_panel.gd` (new) | Controls tab: sliders, toggles, keybind rows; capture mode for rebinding |
| `fps_controller.gd` (edit) | Replace `MOUSE_SENSITIVITY` with `settings.sensitivity()`, which returns hip, or hip × ADS multiplier (× FOV ratio when enabled) while aiming; `aim_t` blends between them |
| `input_router.gd` (edit) | Ignore gameplay actions while a rebind is capturing |

**Config format (`user://settings.cfg`):**
```
[mouse]   hip=0.12  ads_mult=0.8  ads_fov_scale=true  invert_y=false
[movement] sprint_toggle=true
[bindings] jump=[{"type":"key","code":32}], aim=[{"type":"mouse","button":2}], ...
```
- Bindings are stored as physical keycodes, so layouts like AZERTY keep positions.
- Defaults come from `project.godot`'s InputMap, captured on first launch, so `project.godot` remains the source of truth.

**Rules:**
- `pause` (Esc) can't be unbound; `confirm` and `pause` are hidden from the list.
- Mouse wheel bindings are allowed (Apex tap strafe binds forward to the wheel).
- A missing or corrupt config falls back to defaults and is rewritten.

## Tests (headless simulation)
- Save then load round-trips every value and binding.
- Rebinding `jump` to F updates `InputMap`, and an F press triggers jump.
- Conflict detection: binding F to sprint while jump has F reports the conflict; choosing swap leaves jump unbound or with the old key.
- ADS sensitivity: with aim fully in, a 100 px mouse move turns `hip × ads_mult` × 100°.
- Invert Y flips the pitch direction.
- A corrupt `settings.cfg` loads defaults without errors.
- Reset to defaults restores `project.godot` bindings.
- Render: a pause menu and settings panel capture; the panel sits above the art post layer.

## Effort and ownership
- About half a day.
- `settings.gd`, `pause_menu.gd` and `settings_panel.gd` are new files with no conflicts.
- `fps_controller.gd`, `input_router.gd` and `main.gd` (adding the menu node) belong to the main session: send it the edits, or have it build the slice.
- Fits the Astra side of the Opus/Astra split (UI), with the controller hook on the Opus side.
