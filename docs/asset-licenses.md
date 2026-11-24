# RE:Compile FPS: asset sources and licence ledger

Checked online 2026-11-09. A source is **approved** only for the use stated here. Every file imported into the project gets a row in the ledger at the bottom (source URL, pack, licence, credit text, date). Anything without a clear licence stays out. Not legal advice; re-check terms when downloading.

## Approved sources

| Source | Licence (verified 2026-11-09) | Credit required | Commercial use | Restrictions | Use in RE:Compile |
|---|---|---|---|---|---|
| **Kenney** (kenney.nl) | CC0 | No (optional "Kenney"; don't use their logo) | Yes | None | Greybox/prototype pieces, props, crosshair and input-prompt textures |
| **Quaternius** (quaternius.com) | Quaternius Asset License v1.0 | No | Yes, including selling the game | Can't resell or redistribute the assets themselves (raw files, packs, templates); can't claim authorship or imply endorsement | Main 3D source (see packs below) |
| **Poly Haven** (polyhaven.com) | CC0 | No | Yes | Logos and site content excluded | PBR textures (concrete, tile, plaster, metal), HDRIs, scanned props |
| **ambientCG** (ambientcg.com) | CC0 1.0 | No (courtesy credit suggested) | Yes, including raw files in a game | None | Surface textures, decals, grime |
| **freesound.org**, CC0 sounds | CC0 | No | Yes | Don't claim authorship | Footsteps, doors, ambience, creature sounds |
| **freesound.org**, CC-BY sounds | CC-BY | **Yes**, per sound, in the credits screen | Yes | Credit line per sound | Only when no CC0 equivalent exists |

## Conditional sources (check terms per download)

| Source | Status | Why conditional |
|---|---|---|
| **Mixamo** (Adobe) | Use with care | Secondhand sources say it's royalty-free for characters and animations embedded in a game, but raw files can't be redistributed. Confirm Adobe's current FAQ/terms before the first import. Needs Sir's Adobe account |
| **Sonniss GDC bundles** | Use with care | Royalty-free for commercial use in past years, but terms vary by year, and recent bundles forbid AI training. Read the licence file inside the specific bundle |
| **Synty Store** (paid) | Ask before buying | The licence says it is "not limited by game engine", but it also bans making content for "Game Creation Software" products, which is ambiguous for Godot. Get written confirmation from Synty before any purchase |
| **itch.io packs** (PS1/low-poly style) | Per pack | Licences vary from CC0 to custom terms to non-commercial. Only CC0, CC-BY or explicit commercial-game licences |
| **Sketchfab** | Per model | Filter to CC0/CC-BY with "downloadable"; never CC-BY-NC or "Editorial" |

## Rejected

| Source | Reason |
|---|---|
| Lethal Company files (models, textures, sounds, animations, shaders), including modified versions | Copyright of Zeekerss; derivative copies still infringe |
| Project Zomboid files (used as a local reference in the 2D project) | Copyright of The Indie Stone; never shippable |
| freesound **CC-BY-NC** sounds | Non-commercial only |
| Assets with no stated licence, "free for personal use", ripped/"extracted" models | No right to ship |

## Starter shortlist (to download once the project exists)

| Need | Candidate pack | Source / licence | Notes |
|---|---|---|---|
| Campus interiors (rooms, corridors, offices) | Ultimate House Interior Pack, Ultimate Furniture Pack | Quaternius / QAL | Desks, chairs, shelves, cabinets; classrooms built from modular walls plus these |
| Building shell / exterior | Downtown City MegaKit, Modular Streets Pack | Quaternius / QAL | Campus courtyard and building exteriors |
| Sci-fi/lab props | Sci-Fi Essentials Kit | Quaternius / QAL | Computer-lab and research-room dressing |
| Guns | Ultimate Guns Pack, Sci-Fi Modular Gun Pack, Modular Weapons Pack | Quaternius / QAL | Pistol, shotgun, rifle candidates; melee items from the weapons pack |
| Human base meshes | Universal Base Characters, Ultimate Modular Men/Women Packs | Quaternius / QAL | First-person arms (cut from a base mesh) and infected students/staff |
| Enemies | Animated Zombie Pack, Zombie Apocalypse Kit, Ultimate Monsters | Quaternius / QAL | Bases to rework into original enemies (recolour, proportions, kitbash) |
| Animation | Universal Animation Library 1 and 2 | Quaternius / QAL | Retargetable locomotion and attacks; Mixamo only for gaps |
| Greybox | Kenney prototype textures / kits | Kenney / CC0 | Blockout before art pass |
| Textures | Concrete, terrazzo, ceiling tile, painted plaster, linoleum | Poly Haven, ambientCG / CC0 | Downscaled for the lo-fi look |
| Interface | Crosshair Pack, Input Prompts | Kenney / CC0 | Placeholder HUD |
| Fonts | One terminal/mono and one UI face | Google Fonts / SIL OFL | Include the OFL text in the build |
| Sound | Footsteps, doors, fluorescent hum, gunshots, creature vocals | freesound CC0 first, Sonniss bundle second | Every CC-BY sound gets a credits line |

## Import ledger

| Date | File / pack | Source URL | Licence | Credit text | Imported by |
|---|---|---|---|---|---|
| 2026-11-09 | `assets/fonts/JetBrainsMono-Regular.ttf` | JetBrains Mono (github.com/JetBrains/JetBrainsMono) | SIL OFL 1.1 | Ship the OFL text with the build: `JetBrainsMono-OFL.txt` added 2026-11-12 (from github.com/JetBrains/JetBrainsMono) | Claude (migration) |
| 2026-11-12 | `assets/fonts/EBGaramond-Variable.ttf` + `EBGaramond-OFL.txt` | github.com/google/fonts `ofl/ebgaramond/EBGaramond[wght].ttf` (EB Garamond Project Authors) | SIL OFL 1.1 | Ship `EBGaramond-OFL.txt` with the build (included); the font may not be sold on its own | Claude (Grimoire book face, replaces system Georgia) |
| 2026-11-12 | `assets/fonts/ArchivoBlack-Regular.ttf` + `ArchivoBlack-OFL.txt` | github.com/google/fonts `ofl/archivoblack/` (Archivo Black Project Authors, Omnibus-Type) | SIL OFL 1.1 | Ship `ArchivoBlack-OFL.txt` with the build (included); the font may not be sold on its own | Claude (Player ID card headings, replaces system Arial Black) |
| 2026-11-12 | `assets/fonts/Archivo-Variable.ttf` + `Archivo-OFL.txt` | github.com/google/fonts `ofl/archivo/Archivo[wdth,wght].ttf` (Archivo Project Authors, Omnibus-Type) | SIL OFL 1.1 | Ship `Archivo-OFL.txt` with the build (included); the font may not be sold on its own | Claude (Player ID card body text, replaces system Arial) |

| 2026-11-09 | `assets/quaternius/base_characters/` (Superhero male + female glTF, skin/hair/eye textures, `License.txt`) | quaternius.itch.io/universal-base-characters, **Universal Base Characters [Standard]** (free edition: only the Superhero bodies; Regular/Teen are in the paid Source edition) | CC0 1.0 (License_Standard.txt) | None required | Claude (downloaded 2026-11-09, 129 MB zip) |
| 2026-11-09 | `assets/quaternius/animations/` (`UAL1_Standard.glb`, no root motion, + `License.txt`) | quaternius.itch.io/universal-animation-library, **Universal Animation Library [Standard] v2.0** | CC0 1.0 | None required | Claude (downloaded 2026-11-09, 15.9 MB zip) |
| 2026-11-13 | `assets/quaternius/animations_2/` (`UAL2_Standard.glb` no root motion, `Mannequin_F.glb`, `License.txt`, `README.txt`) | quaternius.itch.io/universal-animation-library-2, **Universal Animation Library 2 [Standard]** (zip downloaded by Sir). 43 clips; same 65-bone rig as UAL1 and the base characters (five-finger hands) | CC0 1.0 (License.txt in the zip) | None required | Claude (imported 2026-11-13) |
| 2026-11-13 | `assets/quaternius/nature/` (68 glTF + .bin + 40 textures + `License.txt`) | quaternius.itch.io/stylized-nature-megakit, **Stylized Nature MegaKit [Standard]** (free 68/116 models; zip downloaded by Sir) | CC0 1.0 (License_Standard.txt in the zip) | None required | Claude (imported 2026-11-13) |
| 2026-11-13 | `assets/quaternius/nature/impostors/` (`Pine_5.png`, `DeadTree_1.png`, `impostors.json`) | Far-LOD tree images baked from the Stylized Nature MegaKit models by `tools/bake_tree_impostors.gd` | CC0 1.0 (derived from CC0 models) | None required | Claude (baked 2026-11-13) |
| 2026-11-13 | `assets/BinbunVFX_Vol2/` (merged from 8 free packs by Binbun3D: Battle, Dark Magic, Electric, Elemental Magic, Explosion, Flame, Status, Hit FX; zips downloaded by Sir). Shader-based Godot VFX, `.gd` controllers reviewed: they drive effect nodes only; `OS.shell_open` appears only on editor inspector "Documentation/Rate" buttons, never at runtime. `shared/` kept once (the Explosion copy's stray `print("AA")` debug line dropped) | binbun3d.itch.io (BinbunVFX Vol.2) | CC0 1.0 (`license.txt` in each pack) | None required (author asks for an optional mention of 'Binbun3D') | Claude (imported 2026-11-13) |
| 2026-11-13 | `assets/BinbunVFX_Vol2/BattleFX/` | part of the BinbunVFX Vol.2 row above | CC0 1.0 | None required | Claude |
| 2026-11-13 | `assets/BinbunVFX_Vol2/DarkMagicFX/` | part of the BinbunVFX Vol.2 row above | CC0 1.0 | None required | Claude |
| 2026-11-13 | `assets/BinbunVFX_Vol2/ElectricFX/` | part of the BinbunVFX Vol.2 row above | CC0 1.0 | None required | Claude |
| 2026-11-13 | `assets/BinbunVFX_Vol2/ElementalMagicFX/` | part of the BinbunVFX Vol.2 row above | CC0 1.0 | None required | Claude |
| 2026-11-13 | `assets/BinbunVFX_Vol2/ExplosionFX/` | part of the BinbunVFX Vol.2 row above | CC0 1.0 | None required | Claude |
| 2026-11-13 | `assets/BinbunVFX_Vol2/FlameFX/` | part of the BinbunVFX Vol.2 row above | CC0 1.0 | None required | Claude |
| 2026-11-13 | `assets/BinbunVFX_Vol2/StatusFX/` | part of the BinbunVFX Vol.2 row above | CC0 1.0 | None required | Claude |
| 2026-11-13 | `assets/BinbunVFX_Vol2/StylizedHitFX/` | part of the BinbunVFX Vol.2 row above | CC0 1.0 | None required | Claude |
| 2026-11-13 | `assets/BinbunVFX_Vol2/shared/` | part of the BinbunVFX Vol.2 row above | CC0 1.0 | None required | Claude |
| 2026-11-10 | `assets/wriks/arms/` (`arms.glb`, `arm_albedo_pale.png`, `arm_albedo_dark.png`, `LICENSE.txt`, `README.txt`) | wriks.itch.io/wrad-arms, **WRAD ARMS** by wriks (`WRAD_ARMS.zip`, 2,012,410 bytes; downloaded by Sir) | CC0 1.0 (LICENSE.txt in the zip) | None required; the author asks for 'WRAD ARMS' by wriks (wriks.motorcycles) in credits as a courtesy | Claude (imported 2026-11-10)  **Unused since 2026-11-19** (the player holds only a wand; files kept, not referenced). |
| 2026-11-12 | `assets/akami/buff_debuff_vol1/` (20 PNG icons at 128 px + `LICENSE.txt`, from `FreePack1_Buff_Debuff.zip`, 5.4 MB; the 256/512 px sizes not imported). Used: Burn `debuff_shadow_burn`, Scorched Slow `debuff_slow`, Concuss `debuff_stun`, Cultivate `buff_focus`, Sage Arts `buff_regen_potion` (`scripts/ui/status_icons.gd`) [Sir R12/R14] | akami666.itch.io/buff-debuff-icon-pack-free-vol1, **Buff & Debuff Icon Pack - Free Vol.1** by Akami Assets; the page discloses AI-assisted graphics | CC0 1.0 (LICENSE.txt in the folder) | None required | Claude (Sir chose the pack, 2026-11-12) |
| 2026-11-12 | `assets/wmsu/wmma_seal.png`, `assets/wmsu/hop_logo.png` (256 px): the Western Mindanao State University seal and the WMSU College of Computing Studies logo, re-lettered for the game ("Western Mindanao Magic Academy" / "Guild of the Crimsons"; "House of the Pythons" / "WMMA") in Archivo Black; emblems unchanged; made by `relabel_logos.py` from images Sir supplied | Supplied by Sir (the project belongs to WMSU / CCS, per Sir) | Institutional marks, **not** an open licence: used on the in-game Player ID by Sir's instruction for an institutional project; confirm permission with the institution before any public release | As the institution requires | Claude (Sir supplied and asked for the re-lettering, 2026-11-12) |
**Resolved (2026-11-09):** the missing `Textures/colormap.png` (304 broken references) came from four kits, each with its own texture. Re-downloaded the kits from kenney.nl, confirmed every model byte-identical, split the mixed folder into `car/` and `roads/`, and added each kit's texture and `License.txt`. No folder is skipped by Godot any more.

Provenance note: the old project had no licence files; packs were identified by their file names (Kenney naming and skins). Before any public release, re-download each Kenney pack from kenney.nl so the exact pack and version are on record.

Reference code (not assets, not shipped): `reference/legacy-godot-3d/` (old 3D top-down Godot scripts, scenes, weapon resources, IMPORT_CONVENTIONS.md) and `reference/legacy-web/` (web prototype's mini Python/SQL/C++/JS interpreters, game data, tests: ideas for the terminal puzzles).

Sources consulted: kenney.nl/support, quaternius.com/license.html, polyhaven.com/license, docs.ambientcg.com/license, freesound.org/help/faq, syntystore.com/pages/one-time-purchase-licence, Adobe community Mixamo FAQ thread, third-party Sonniss bundle summaries.

## Code addons

| Date | Path | Source | Licence | Attribution | Added by |
|---|---|---|---|---|---|
| 2026-11-09 | `addons/dot_player_controller/` | github.com/modcommunity/dot-fps-controller @ 9d31059 (2026-11-08) | MIT | Keep `LICENSE` in the folder and credit "dot-player-controller contributors" | Claude (R1 movement base) |
| 2026-11-09 | `addons/dot_core/` | github.com/modcommunity/dot-core @ a4959dd (2026-11-08); required by the controller | MIT | Keep `LICENSE` in the folder | Claude |
| 2026-11-09 | `addons/dot_player/` | github.com/modcommunity/dot-player @ 766c085 (2026-11-07); required by the controller | MIT | Keep `LICENSE` in the folder | Claude |

Upstream self-tests on Godot 4.7.2 before adoption: 874 passed, 0 failed (movement, fps_controller, surf, classic, controller, motor determinism). Not enabled as editor plugins yet (class names work without it).

## Archived assets (removed from the project 2026-11-11)

Moved to `outputs/RECompile-Archive/2026-11-11/` (outside the Godot project, not shipped), except the campus furniture, which is in `reference/legacy-campus/` (see its row). Unused after the Grimoire pivot: shooter guns, campus vehicles/roads/buildings, survival props, Kenney characters and their animations. Rows kept for provenance. `assets/kenney/furniture/` (the campus lab) was moved by the main session to `reference/legacy-campus/assets/` (Godot-ignored) on 2026-11-12.

| Date | Path | Source | Licence | Attribution | Added by |
|---|---|---|---|---|---|
| 2026-11-09 | `assets/kenney/building/` (79 .glb + `Textures/colormap.png` + `License.txt`) | kenney.nl/assets/building-kit, **Building Kit 1.0** (2025-03-29); all 79 files byte-identical to the download | CC0 | None required | Claude (re-downloaded 2026-11-09) |
| 2026-11-09 | `assets/kenney/survival/` (80 .glb + texture + licence) | kenney.nl/assets/survival-kit, **Survival Kit 2.0** (2024-04-03); all 80 byte-identical | CC0 | None required | Claude (re-downloaded 2026-11-09) |
| 2026-11-09 | `assets/kenney/car/` (50 .glb + texture + licence; split out of the old furniture folder) | kenney.nl/assets/car-kit, **Car Kit 3.1** (2026-04-02); all 50 byte-identical | CC0 | None required | Claude (re-downloaded 2026-11-09) |
| 2026-11-09 | `assets/kenney/roads/` (95 .glb + texture + licence; split out of the old furniture folder) | kenney.nl/assets/city-kit-roads, **City Kit (Roads) 2.2** (2026-10-10); all 95 byte-identical | CC0 | None required | Claude (re-downloaded 2026-11-09) |
| 2026-11-09 | `assets/kenney/characters/` (character_base.fbx + 12 skins incl. zombie A/C/female/male) | kenney.nl (Animated Characters) | CC0 | None required | Claude (migration) |
| 2026-11-09 | `assets/kenney/animations/` (player + shambler idle/run/jump .fbx) | kenney.nl Animated Characters: **corrected provenance** (was logged as Mixamo). The clips drive the same 58-bone Kenney rig (`LeftFootCtrl`, `HipsCtrl`, ...) and the old project's own path was `assets/animations/`. Moved from `assets/mixamo/`; the old derived `.res` libraries were dropped | CC0 | None required | Claude (migration) |
| 2026-11-10 | `assets/quaternius/guns/` (`Pistol_5`, `AssaultRifle_2`, `Shotgun_2`, `Bayonet` .fbx + `License.txt`; `viewmodels/*.tscn` built from them by `tools/build_viewmodels.gd`) | opengameart.org/content/low-poly-guns-pack, **Ultimate Gun Pack by Quaternius** (`ultimate_gun_pack_by_quaternius.zip`, 7,375,704 bytes; also quaternius.itch.io/50-lowpoly-guns). The zip ships no licence file; provenance recorded in `License.txt` | CC0 1.0 | None required | Claude (downloaded 2026-11-10) |
| 2026-11-09 | `assets/kenney/furniture/` → **now at `reference/legacy-campus/assets/kenney/furniture/`** (moved 2026-11-12 by the main session; Godot-ignored, not shipped) (140 .glb, untextured: furniture, bathroom, kitchen, bedroom) | kenney.nl/assets/furniture-kit (identified by camelCase file names; carried from the old project) | CC0 | None required | Claude (migration) |
| 2026-11-13 | `assets/BinbunGrass/` = `assets/BinbunGrass/src/` (grass + ground shaders; `grass_fade` / `ground_lit` are our derived copies, dither include, grass atlas/shape PNGs, palette, 2 materials; demo scene and .xcf dropped) | binbun3d.itch.io/godot-grass, **Godot Grass Shader by Binbun** (`SourceCode.zip` from Sir's Downloads). The zip ships no licence file; CC0 per the author's itch page and forum post; provenance in `LICENSE.txt` | CC0 1.0 | None required | Claude (from Sir's download, 2026-11-13) |
| 2026-11-13 | `assets/BinbunSky/` = `assets/BinbunSky/shader/` + `assets/BinbunSky/textures/` (sky shader, triplanar include, 7 cloud noise textures) | binbun3d.itch.io/godot-skies, **Godot Skies by Binbun** (`SourceCode (1).zip`). No licence file in the zip; CC0 per the itch page and godotshaders.com post; provenance in `LICENSE.txt` | CC0 1.0 | None required | Claude (from Sir's download, 2026-11-13) |
| 2026-11-13 | `assets/quaternius/props/` (Anvil_Log, Bench, Barrel, Crate_Wooden, Torch_Metal, Cauldron, Pouch_Large, Scroll_1, Book_5, Bag, and 2026-11-14 Coin, Coin_Pile, Coin_Pile_2 .gltf/.bin + trim textures downscaled 2048/4096 -> 512 px for the pixel look; `License.txt`) | quaternius.com, **Fantasy Props MegaKit [Standard]** by Quaternius (`Fantasy Props MegaKit[Standard].zip` from Sir's Downloads) | CC0 1.0 | None required | Claude (from Sir's download, 2026-11-13) |
| 2026-11-14 | `assets/BinbunVFX/` = `assets/BinbunVFX/portal_vfx/` + `assets/BinbunVFX/shared/` (simple portal scene, controller script, 4 shaders + dithering include, patched to the 12 FPS `pixel_fx` include; placeholder texture) | binbun3d.itch.io/godot-portal-vfx, **Portal VFX - Godot 3D (free)** by Binbun (`PortalVFX` folder from Sir's Downloads). No licence file shipped; the itch page lists CC0 v1.0 (checked 2026-11-14); provenance in `LICENSE.txt` | CC0 1.0 | None required | Claude (from Sir's download, 2026-11-14) |
| 2026-11-14 | `assets/BinbunVFX/loot_effects/` + `assets/BinbunVFX/shared/script/`, `shared/shader/util/`, `shared/texture/icon/` (12 loot effects: 6 floating, 6 ground; `vfx_loot.gd` / `vfx_effect.gd` reviewed: they set shader, light and particle properties only; 4 shaders patched to the 12 FPS `pixel_fx` include) | binbun3d.itch.io/loot-vfx, **Loot VFX - Godot 3D** by Binbun (`GodotLootVFX` folder from Sir's Downloads, the free "Loot VFX" file). No licence file shipped; the itch page lists "Creative Commons Zero v1.0 Universal" (checked 2026-11-14) | CC0 1.0 | None required | Claude (from Sir's download, 2026-11-14) |

## Player ID card (2026-11-20)

| Date | Path | Source | Licence | Attribution | Added by |
|---|---|---|---|---|---|
| 2026-11-20 | `assets/view_id/` = `academy_id.glb` (the Academy credential card with Draw / FlipToBack / FlipToFront / Hold clips), `academy_id_front.png`, `academy_id_back.png` | `academy_id.glb` is byte-identical to Sir's `Desktop/GAME ASSETS/Player ID/Godot/Player ID.glb` (MD5 f5e26a53..., checked 2026-11-20). The two PNGs were added by another session with no recorded source: that session should confirm them | Sir's own asset pack | None required | another session (ledger row by Claude, 2026-11-20, from the MD5 match) |

## Tropical plants (2026-11-20)

| Date | Path | Source | Licence | Attribution | Added by |
|---|---|---|---|---|---|
| 2026-11-20 | `assets/tropical/` = `narra_tree.glb`, `mango_tree.glb`, `banana_tree.glb`, `bamboo_clump.glb` (two opaque, double-sided materials each with embedded painted albedo maps; per-face normals) | Sir's `Desktop/GAME ASSETS/Mage Arena Style` (Graphics.md). Geometry and textures made by Sir with his tool Astra; the pack's Mage Arena reference supplied only measured tints and texture sizes, no files (names checked: per-plant stems/leaves, no game asset names) | Sir's own work: cleared to use [Sir, 2026-11-20] | None required | Claude (from Sir's GAME ASSETS, 2026-11-20) |
| 2026-11-20 | `assets/tropical/impostors/` (`Narra/Mango/Banana/Bamboo.png`, `impostors.json`) | baked from the plants above by `tools/bake_tree_impostors.gd` | as the plants | None required | Claude (2026-11-20) |

## Held grimoire and Ember Wand (2026-11-20)

| Date | Path | Source | Licence | Attribution | Added by |
|---|---|---|---|---|---|
| 2026-11-20 | `assets/held_grimoire/` = `ember_wand.glb` (the Ember Wand and its 46 movement/gesture clips; parts Shaft, LeatherGrip, BrassCollar, Pommel, EmberCrystal, Tip, matching the project's own code-built wand; generator Godot 4.7.2) | Sir's `Desktop/GAME ASSETS/Ember Wand` (identical to `Held Grimoire/Godot/assets/Ember Wand.glb`, MD5 c74f666b...) | Sir's own asset pack (no third-party source found) | None required | Claude (from Sir's GAME ASSETS, 2026-11-20) |
| 2026-11-20 | `assets/held_grimoire/` = `rose_compass_grimoire.glb` (the held book: cover, folios, Equip/Idle/PageFlip1-4 clips) | Sir's `Desktop/GAME ASSETS/Held Grimoire/Godot/assets/Rose Compass Grimoire.glb` (MD5 db90da30...) | **NOT CLEARED.** Its rig and meshes match the Dragon Grimoire, which comes from `Mage Arena - Book Source.zip` (files extracted from Mage Arena): all 43 armature/bone names, the `magebookbase` / `magebookp1-4` meshes and the PageFlip1-4 clips are shared; only the materials differ. Sir was told and chose to use it as-is (2026-11-20). Do not ship or publish without replacing it or clearing the rights. | n/a | Claude (at Sir's instruction, 2026-11-20) |
| 2026-11-20 | `scripts/player/held_rig.gd`, `scripts/ui/page_ink.gd`, `scripts/player/ember_wand.gd` (ported from the pack's HeldRig.gd, PageInk.gd, WandView.gd); fonts EB Garamond and Archivo already in `assets/fonts/` (OFL) | Sir's `GAME ASSETS/Held Grimoire` | Sir's own scripts; fonts SIL OFL 1.1 | OFL texts in `assets/fonts/` | Claude (2026-11-20) |


## Map 1 layout pass (2026-11-20)

| Date | Path | Source | Licence | Attribution | Added by |
|---|---|---|---|---|---|
| 2026-11-20 | `assets/kenney_fantasy_town/` = 13 GLBs used for the camp's distant town and keep (`wall`, `wall-window-glass`, `wall-window-shutters`, `wall-door`, `wall-wood`, `wall-wood-window-glass`, `wall-block`, `roof`, `roof-gable`, `roof-point`, `roof-high-point`, `pillar-stone`, `chimney`), `assets/kenney_fantasy_town/Textures/colormap.png` (the kit's colour map), `License.txt` | Kenney **Fantasy Town Kit 2.0** (kenney.nl/assets/fantasy-town-kit; `kenney_fantasy-town-kit.zip`, 3.9 MB, downloaded with Sir's approval, relayed 2026-11-20) | CC0 1.0 (License.txt in the kit) | Kenney (www.kenney.nl), not required | Claude (2026-11-20) |
| 2026-11-20 | `assets/textures/map1/earth.png` (128 px tiling ground detail, the camp trail) | Sir's `Desktop/GAME ASSETS/Dark Forest Layouts/Earth.png` ("an original 128 px tiling ground detail", Implementation Guide.md) | Sir's own pack | None required | Claude (2026-11-20) |
| 2026-11-20 | `assets/shaders/map1/` (`bamboo`, `mist` adapted from the same pack's Bamboo/Mist.gdshader; `fog_banks`, `fog_sheet` written for the game) | Sir's `Dark Forest Layouts` pack; project code | Sir's own pack / project | None required | Claude (2026-11-20) |

## Infected Hostiles (2026-11-20)

| Date | Path | Source | Licence | Attribution | Added by |
|---|---|---|---|---|---|
| 2026-11-20 | `assets/infected_hostiles/` = `blighted_sprite.glb`, `forest_ghoul.glb`, `kostas_mortus.glb` (skinned replacements for the three hostiles, 25 clips each, five-digit hands; the Ghoul's bow and quiver) and their subclass scripts, plus `Quaternius License.txt` and `Animation sources.json` copied from the pack | Sir's `Desktop/GAME ASSETS/Infected Hostiles` pack (GLBs byte-identical, MD5 939e51b6 / a86ace4d / 8a286552), built in `Documents/Codex/Infected Hostiles Study` | Bodies: Quaternius Universal Base Characters, CC0 1.0. Bow, quiver, finger rigs and the bow pose: authored for the pack. **Animations: NOT CLEARED.** Retargeted from Valve's Left 4 Dead 2 animation banks (donor clip per slot in `Animation sources.json`); the pack's README states public distribution rights for those motions have not been established. Same status as the Rose Compass book: replace before any public release | Quaternius (bodies); Valve (source motions) | Claude (ledger, 2026-11-20; provenance relayed by the coordinating session and checked against the pack) |
| | Status | Staged only: the game still loads `scripts/actors/` (not referenced by any game script) | | | |

## Generated skill-icon artwork (2026-11-17)

`assets/ui/skill-icons/`: images generated with the built-in image generation tool at the user's request, using user-supplied Brand, Estes and Neeko ability icons as visual references. Includes the original fire pair, cyan set and green/teal rework. These are generated project artwork, not extracted game textures; no Riot or Moonton authorship or endorsement is claimed. The supplied reference images were not copied into the project. This entry records provenance, not a third-party licence grant.

## Dark Forest asset swap (2026-11-24)

| Date | Path | Source | Licence | Attribution | Added by |
|---|---|---|---|---|---|
| 2026-11-24 | `assets/hostiles/` = `blighted_sprite.glb`, `forest_ghoul.glb`, `kostas_mortus.glb` and their embedded 64 px textures (imported copies land beside them) | Sir's `Desktop/GAME ASSETS/Finalized Hostiles/{Blighted Sprite - Retro, Forest Ghoul - Ashveil Retro, Kostas Mortus - Iron Ram Retro}` (SHA-256 daf2df24… / 657e8ac5… / c5bdbca2…, byte-identical to the approved files) | Sir's own pack, authored in this project's art direction; the animations are the pack's own (the earlier `assets/infected_hostiles/` set retargeted Left 4 Dead 2 motions and is **not** used by these actors) | None required | Claude (at Sir's instruction, 2026-11-24) |
| 2026-11-24 | `assets/quaternius/nature/`, `assets/tropical/`, `assets/textures/map1/earth.png`, `assets/map1_vista/` payloads replaced in place (284 files: 68 `.gltf` + 68 `.bin` + textures/impostors/vista) from the approved Dark Forest retro remodel. `assets/BinbunGrass/` deliberately untouched: the project's original Binbun masks, atlas, shaders and materials remain the default | Sir's `Desktop/GAME ASSETS/Dark Forest Retro Remodel/assets_retro` (`manifest.json`, `environment_manifest.json`) | Quaternius Artist License (derivatives of the Quaternius nature packs) + Sir's own tropical and map1 artwork | Quaternius | Claude (2026-11-24) |
