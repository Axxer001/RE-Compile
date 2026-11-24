# Map 1 environmental art handoff for Opus

Target: RE:Compile FPS, Godot 4.7.2, Forward+. Assets are integrated through the existing map builder. Dimensions and positions are in metres, Y up. These are static scenery and procedural shaders. They have no armature, animation library, gameplay event frames or collision changes.

## Gate curtains

`res://assets/shaders/map1/seal_mist.gdshader` runs on the existing gate QuadMesh. Each curtain has its own material; all share the seamless Binbun `clouds_01.tres`. The five initialization/update sites in `scripts/world/map1_world.gd` now set `cover`. Drive the particular curtain instance when opening or sealing it. Existing seal timing is 2.5 s.

| Uniform | Default | Use |
| --- | --- | --- |
| `cover` | 0 | Animate continuously from 0 open to 1 sealed. |
| `tint` | RGB (0.102, 0.122, 0.110) sRGB | Matches forest fog #1a1f1c. |
| `soft_distance` | 2.2 m | Geometry intersection feather, 0.1–6 m. |
| `wind` | (0.018, 0.006) UV/s | Speed and direction of scrolling noise. A practical range is ±0.04 per axis. |
| `noise_tex`, `depth_tex` | Shared seamless cloud texture; viewport depth supplied by renderer | Art texture uses linear mipmaps. Depth uses the nearest level-zero sample so the intersection follows the visible surface. |

The curtain feathers at its four edges and fades as the eye approaches from 4 m to 0.8 m. Physical access remains controlled by the existing map logic.

## Forest ground mist

`res://assets/shaders/map1/fog_banks.gdshader` uses the existing player-following 64 × 14 × 64 m FogVolume in `scripts/world/map1_fog.gd`. The shader samples a world-space field and fades density over the outer 28% of the normalized half-extents. Crossing a tile does not start a separate noise field. The environment retains its 24 m volumetric budget and existing distance fog.

| Uniform | Default | Runtime owner and useful range |
| --- | --- | --- |
| `noise` | Bound at setup to seamless 64 × 32 × 64 NoiseTexture3D | Repeat sampling with linear filtering; fixed resource. |
| `drift` | (0,0,0) m | Accumulated wind displacement from the fog driver, horizontal speed 1–2.2 m/s. |
| `density` | 0.05 | Driver eases toward 0.012 camp, 0.10 pathway, 0.16 combat. Sealing can multiply the target by up to 1.6. |
| `ground_y` | 0 m | Sampled terrain height under the player. |
| `height` | 9 m | Vertical falloff above the sampled ground. Keep positive; 5–10 m fits the volume. |
| `tint` | (0.30,0.35,0.32) sRGB | Fixed scattering tint. |

## Camp vista and sky

Instantiate `res://assets/map1_vista/valley_layers.tscn` once under Town at the campfire, world (75,0,129), identity rotation and scale. The builder already does this. The positive-Z opening frames the existing Kenney town at (75,-7,240). The two mesh resources, `highlands.obj` and `woodline.obj`, contain the broad far relief and the nearer irregular silhouette. Two soft haze cards sit 67 and 85 m down the valley, beyond the 24 m volumetric range. Their shared curtain material overrides `cover` to 0.34 and `tint` to (0.34,0.40,0.43). For artistic tuning keep cover around 0.2–0.45. Neither card participates in gate logic.

Retain the existing Binbun-derived `res://assets/shaders/map1/valley_sky.gdshader`. The builder binds `cloud_tex_01` and `cloud_tex_02` to the matching resources in `res://assets/BinbunSky/textures/clouds/`. Both samplers explicitly request linear mipmaps.

| Uniform | Default | Animation or tuning |
| --- | --- | --- |
| `amount` | 1 | Runtime 1 at camp to 0 in forest. The same factor now scales TownGlow energy (0–4) and window emission (0–3.2). |
| `sky_night`, `horizon_night`, `horizon_exponent` | (0.035,0.053,0.078), (0.076,0.094,0.13), 2 | Fixed grading. |
| `cloud_color`, `cloud_tiling`, `wind_speed` | (0.16,0.18,0.22), (1,1), (0.08,0.03) | Fixed art settings; the shader advances time. |
| `cloud_density`, `cloud_depth`, `cloud_shape_exponent`, `cloud_occlude_exponent` | 0.7, 2, 2, 1 | Fixed for Map 1. Keep density above zero if tuning; it divides the cloud sample. |
| `moon_dir`, `moon_scale`, `moon_strength`, `moon_color` | (-0.19,0.23,0.96), 0.012, 1, (0.62,0.67,0.70) | Fixed world direction and grade. |

## Bamboo entrance

The existing `CampBamboo` MultiMesh uses three staggered planting bands, centered approximately 1.2, 5.8 and 12 m behind the camp boundary. The generator proposes 1,250 stems before rejecting positions inside the opening and pathway clearance. It retains the (75,0,115) mouth and the existing path colliders. Each stem uses the shared cylinder, local Y from −0.5 to +0.5; `INSTANCE_CUSTOM.r` controls darkening toward the outer ranks.

`res://assets/shaders/map1/bamboo.gdshader` exposes `tip_sway_m` (0.48, range 0–1.2 m) and `sway_speed` (0.72, range 0–2). Wind is coherent in world space. Sway amplitude is zero at the base. The tip amplitude is modulated by a two-frequency gust. Both uniforms can stay constant during gameplay.

## Camera QA

Reproduction: Map1 Review/Astra visual pass/capture.gd, gameplay scene, seed 7, 960 × 540, Forward+. The adjacent render log records feet position, yaw, pitch and fog depth for each PNG. Compare Valley, Left bank, Entrance, Avenue, Canopy, Seal, Open route and the three Field seam captures. The Seal capture explicitly places a fully closed test curtain. The simulation suite exercises the live sealing sequence separately.

The first pass exposed a squared-off trail start and an abrupt bank near world Z=146, seen from (75,0,134) at yaw 180° and 222°. The trail now fades through vertex alpha over 11 m and shoulder relief blends across the join over 18 m. The map test also exposed town lights persisting after the sky faded; both light sources now follow the dome fade.
