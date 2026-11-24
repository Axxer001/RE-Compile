"""Paired eager/streamed tree captures with unchanged source and real GPU."""
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
from benchmark_terrain import ROOT, sources

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--out", type=Path, default=ROOT / "evidence" / "tree-chunks")
parser.add_argument("--reverse", action="store_true")
args = parser.parse_args()
out = args.out.resolve()
out.mkdir(exist_ok=False)
pinned = sources()
(out / "sources.json").write_text(json.dumps(pinned, indent=2))
records = []
for scenario in ["generation", "traversal"]:
    for mode in (["streamed", "eager"] if args.reverse else ["eager", "streamed"]):
        assert sources() == pinned, "Source changed"
        dest = out / f"{scenario}-{mode}"
        dest.mkdir()
        env = os.environ.copy()
        env.pop("RC_EAGER_TREES", None)
        env.pop("RC_STREAM_TREES", None)
        if mode == "eager": env["RC_EAGER_TREES"] = "1"
        else: env["RC_STREAM_TREES"] = "1"
        cmd = [shutil.which("godot_console"), "--path", str(ROOT), "res://tests/performance/baseline.tscn", "--", f"--scenario={scenario}", f"--out={dest}"]
        if scenario == "traversal": cmd.append("--residents")
        with (dest / "run.log").open("w") as log:
            code = subprocess.run(cmd, env=env, stdout=log, stderr=subprocess.STDOUT, timeout=210).returncode
        lines = (dest / "run.log").read_text().splitlines()
        results = [json.loads(line[7:]) for line in lines if line.startswith("RESULT ")]
        errors = [line for line in lines if "ERROR:" in line or "SCRIPT ERROR" in line]
        valid = code == 0 and len(results) == 1 and not errors and sources() == pinned and results[0].get("status") == "PASS"
        record = dict(scenario=scenario, mode=mode, valid=valid, errors=errors, results=results)
        records.append(record)
        (out / "summary.json").write_text(json.dumps(records, indent=2))
        print(scenario, mode, "valid", valid, flush=True)
        assert valid, "Invalid capture; see log"
