"""Sequential combat/traversal isolation; removed work is diagnosis, not acceptance."""
import argparse
import json
import os
import shutil
import subprocess
from pathlib import Path
from benchmark_terrain import ROOT, sources

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--out", type=Path, required=True)
parser.add_argument("--counts", type=int, nargs="+", default=[20, 250], choices=[20, 250])
parser.add_argument("--scenario", choices=["combat","traversal"], default="combat")
parser.add_argument("--script-profile", action="store_true", help="Emit Godot function profiles; these timings include profiler overhead")
parser.add_argument("--variants", nargs="+", default=["baseline"], choices=["baseline", "legacy_burn_sort", "no_shadows", "no_fog", "no_tree_detail", "no_enemy_models", "no_animation", "no_burn_fx", "no_particle_draw", "no_far_trees", "no_tree_collision", "no_residents", "no_grass"])
args = parser.parse_args()
out = args.out.resolve()
out.mkdir(parents=True, exist_ok=False)
pinned = sources()
(out / "sources.json").write_text(json.dumps(pinned, indent=2))
env = os.environ.copy()
for key in list(env):
    if key.startswith("RC_"): env.pop(key)
records = []
for count in (args.counts if args.scenario == "combat" else [0]):
    for variant in args.variants:
        assert sources() == pinned, "Source changed"
        dest = out / f"{count}-{variant}"
        dest.mkdir()
        cmd = [shutil.which("godot_console"), "--path", str(ROOT), "res://tests/performance/crowd_profile.tscn", "--", f"--scenario={args.scenario}", f"--variant={variant}", f"--out={dest}"]
        if args.scenario == "combat": cmd.append(f"--enemies={count}")
        elif variant != "no_residents": cmd.append("--residents")
        if args.script_profile: cmd[1:1] = ["--debug", "--profiling"]
        with (dest / "run.log").open("w") as log:
            code = subprocess.run(cmd, cwd=ROOT, env=env, stdout=log, stderr=subprocess.STDOUT, timeout=240).returncode
        lines = (dest / "run.log").read_text().splitlines()
        results = [json.loads(line[7:]) for line in lines if line.startswith("RESULT ")]
        errors = [line for line in lines if "ERROR:" in line or "SCRIPT ERROR" in line]
        valid = code == 0 and len(results) == 1 and not errors and sources() == pinned and results[0].get("status") == "PASS"
        if args.script_profile: valid = valid and any(line.startswith("ACCUMULATED:") for line in lines)
        profile = json.loads((dest / "render-profile.json").read_text()) if (dest / "render-profile.json").exists() else {}
        records.append(dict(count=count, scenario=args.scenario, variant=variant, script_profiler=args.script_profile, valid=valid, errors=errors, results=results, profile=profile))
        (out / "summary.json").write_text(json.dumps(records, indent=2))
        metrics = results[0].get("metrics", {}) if results else {}
        print(count, variant, "valid", valid, "p95", metrics.get("p95_ms"), "GPU", profile.get("gpu_ms"), flush=True)
        assert valid, "Invalid capture; inspect retained log"
