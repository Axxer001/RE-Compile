# Review fixes — 2026-11-13

Implemented temporary-file profile saves with previous-readable-save backup, backup load recovery, save-failure signal and UI notice; reject exhausted map generation before replacing world state; updated README to forest/Grimoire runtime; labelled stress workload and added post-update minimum loads, full-load frame fraction, real-clock sample duration and separate generation/scatter timing.

Simulation: 685 checks PASS, no ERROR/SCRIPT ERROR lines in evidence/review-fixes-final.log. Asset UID warnings and exit object leaks remain. Import completed under elevated access; initial sandbox run could not access Godot editor directories.

GPU stress: FAIL existing 7.7 ms p95 gate; p95 16.35 ms, average 9.35 ms, 2140 frames over 20.012 s, 950 trees, 20 enemies. Full load in 53.13% of frames, minimum 38 projectiles and 0 burning enemies after update. Generation/scatter 1000.238 ms, excludes navigation rebuild. Single diagnostic run, not a repeatable performance baseline; other verification processes overlapped portions of execution. No threshold changed. See evidence/review-fixes-performance.log.

Separate full-gameplay generation/traversal/combat benchmarking remains pending. This patch improves existing stress reporting, not a claim to have completed those three benchmarks. No exported executable rebuilt; Launch.cmd may select an older build. No Git repository present.
