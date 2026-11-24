"""Run sequential, source-pinned crowd captures; requires the real GPU display."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import time

ROOT = Path(__file__).resolve().parents[1]

def sources():
    paths = [ROOT / "project.godot"]
    for folder in ["scripts", "scenes", "data", "tests/performance"]:
        paths += [p for p in (ROOT / folder).rglob("*") if p.suffix in {".gd", ".tscn", ".tres", ".json", ".gdshader"}]
    return {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(paths)}

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--counts", type=int, nargs="+", choices=[20, 50, 100, 200, 250, 300], default=[20, 50, 100, 200, 250, 300])
    parser.add_argument("--trials", type=int, default=3)
    parser.add_argument("--cold-pool", action="store_true")
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args()
    if args.trials < 1: parser.error("trials must be positive")
    exe = shutil.which("godot_console") or shutil.which("godot")
    if not exe: parser.error("Godot is not on PATH")
    out = args.out.resolve()
    out.mkdir(parents=True, exist_ok=False)
    pinned = sources()
    (out / "sources.json").write_text(json.dumps(pinned, indent=2))
    records = []
    for trial in range(1, args.trials + 1):
        for count in args.counts:
            if sources() != pinned: raise SystemExit("Source changed: stopped before starting another capture")
            dest = out / f"{count}-{trial}"
            dest.mkdir()
            cmd = [exe, "--path", str(ROOT), "res://tests/performance/baseline.tscn", "--", "--scenario=combat", f"--enemies={count}", f"--out={dest}"]
            if args.cold_pool: cmd.append("--cold-pool")
            start = time.monotonic()
            with (dest / "run.log").open("w") as log:
                try:
                    code = subprocess.run(cmd, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT, timeout=210).returncode
                except subprocess.TimeoutExpired:
                    code = "timeout"
            text = (dest / "run.log").read_text()
            lines = [line[7:] for line in text.splitlines() if line.startswith("RESULT ")]
            result = json.loads(lines[0]) if len(lines) == 1 else {}
            errors = [line for line in text.splitlines() if any(s in line for s in ["SCRIPT ERROR", "Parse Error", "ERROR:"])]
            unchanged = sources() == pinned
            record = {"enemies": count, "trial": trial, "exit": code, "seconds": round(time.monotonic() - start, 2), "source_unchanged": unchanged, "errors": errors, "result": result}
            record["capture_valid"] = code == 0 and unchanged and not errors and result.get("status") == "PASS"
            records.append(record)
            (out / "summary.json").write_text(json.dumps(records, indent=2))
            metrics = result.get("metrics", {})
            print(count, trial, "valid", record["capture_valid"], "p95", metrics.get("p95_ms"), "sim_ms", metrics.get("simulation_ms_per_tick"), flush=True)
            if not record["capture_valid"]: raise SystemExit("Capture interrupted or invalid: inspect the retained log")
    if not all(r["capture_valid"] for r in records): raise SystemExit("One or more workload captures failed")

if __name__ == "__main__":
    main()
