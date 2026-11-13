# RE:Compile — 3D Asset Import Conventions

> Read this before dropping any `.glb`, `.gltf`, or `.fbx` file into the project.
> Violations here cause collider desync, broken sockets, and scene-reload crashes.

---

## 1. Coordinate System & Scale

| Setting | Required Value |
|:--|:--|
| **Forward axis** | `-Z` (Godot native; Blender default matches) |
| **Up axis** | `+Y` |
| **Scale** | `1 Godot unit = 1 metre` |
| **Export scale** | `1.0` (no rescaling in importer; fix in source DCC) |

**Mixamo rigs:** Export as `.glb` from Mixamo with `Without Skin` for base T-pose, `With Skin` for animation clips. Import scale must be `0.01` → `1.0` corrected in the **Blender** export step (apply scale before export).

---

## 2. Required Scene Socket Hierarchy

Every player scene (`player.tscn`, `player_female.tscn`) **must** contain these named nodes before mesh/rig attachment:

```
CharacterBody3D (player.gd)
├── CollisionShape3D          — CapsuleShape3D; H=1.8m, R=0.3m (male); H=1.53m, R=0.26m (female)
├── ModelRoot                 — Node3D; parent for skeletal mesh swap
│   └── [SkeletonRoot]        — Skeleton3D + MeshInstance3D attached here post-import
├── RightHandSocket           — Marker3D; weapon/tool attach point (matches hand bone via BoneAttachment3D)
├── FlashlightPivot           — Node3D; rotates with aim direction (driven by _aim_at_mouse)
│   └── Flashlight            — SpotLight3D; range=12m, angle=25°, attenuation=0.6
├── ProjectileSpawn           — Marker3D; muzzle/throw origin (child of RightHandSocket or FlashlightPivot)
├── MeleeHitbox               — Area3D; BoxShape3D 0.6×0.6×1.0m offset 1.0m forward; Layer=4 (Hitboxes)
├── ShoveHitbox               — Area3D; BoxShape3D 0.8×0.8×0.6m offset 0.8m forward; Layer=4 (Hitboxes)
├── Hurtbox3D                 — Area3D (hurtbox_3d.gd); CapsuleShape matching CollisionShape; Layer=5 (Hurtboxes)
└── AnimationTree             — AnimationTree (optional; add after rig import)
```

---

## 3. Collision Layer Matrix

Assign layers in **Project → Project Settings → Layer Names → 3D Physics**:

| Layer | Name | Who uses it |
|:--:|:--|:--|
| 1 | `Environment` | Static floor/walls/props (MeshInstance3D + StaticBody3D) |
| 2 | `Player` | `CharacterBody3D` player nodes |
| 3 | `Enemies` | Infected shambler & variants |
| 4 | `Hitboxes` | Melee / shove / projectile `Area3D` attack volumes (scan Layer 3 & 2) |
| 5 | `Hurtboxes` | Damageable `Area3D` receivers (on player & enemies) |
| 6 | `Interactables` | Terminals, doors, extraction zone, props |
| 7 | `Throwables` | Molotov / grenade `RigidBody3D` in-flight |

**Mask rules:**
- `Hitboxes` (L4) → scan `Hurtboxes` (L5) only
- `Player` (L2) → collides with `Environment` (L1) + `Interactables` (L6) + `Throwables` (L7)
- `Enemies` (L3) → collides with `Environment` (L1) + `Player` (L2)

---

## 4. AnimationTree State Machine Contract

Add an `AnimationTree` node to the player scene after Mixamo rigs are imported. Plug clips into these named states:

| State Name | Trigger | Source Clip |
|:--|:--|:--|
| `Idle` | velocity ≈ 0, `State.IDLE` | Mixamo — Idle Standing |
| `Walk` | moving, not sprinting | Mixamo — Walking |
| `Run` | `is_sprinting == true` | Mixamo — Running |
| `Attack_Melee` | `_execute_melee_attack()` | Mixamo — Punch / Swing |
| `Shove` | `_execute_shove()` | Mixamo — Push |
| `Shoot` | `_execute_ranged_attack()` | Mixamo — Shoot Pistol / Throw |
| `Interact` | Reserved — terminal E-key | Mixamo — Typing / Reaching |

BlendSpace1D key: `parameters/MoveBlend/blend_amount` driven by `velocity.length() / sprint_speed` (0.0–1.0).

> **All `animation_tree.set(...)` calls in `player.gd` are guard-checked** (`if animation_tree == null: return`). The game runs identically with or without the tree present.

---

## 5. Environment & Prop Import Rules

| Rule | Detail |
|:--|:--|
| **Collision suffix** | Kenney/external props: append `-col` to mesh name in Blender for auto-generated `StaticBody3D + CollisionShape3D` on import |
| **Material overrides** | Use Godot `StandardMaterial3D` overrides; never rely on baked FBX materials |
| **Texture format** | `.png` or `.webp`; max 1024×1024 for props, 2048×2048 for characters |
| **LOD** | Not required at MVP; flag meshes with `>5000 tris` for future LOD pass |
| **Shader** | `GL Compatibility` renderer only — no Vulkan-only shader features |
