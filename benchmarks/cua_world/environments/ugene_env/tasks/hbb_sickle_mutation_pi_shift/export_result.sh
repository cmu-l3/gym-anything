#!/bin/bash
echo "=== Exporting task results ==="

# Capture final state
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

RESULTS_DIR="/home/ga/UGENE_Data/results"

# Use python to safely read all output files and bundle them into a single JSON artifact
# This completely bypasses issues with newlines and quotes in bash escaping.
python3 << PYEOF
import json
import os
import time

results_dir = "${RESULTS_DIR}"
res = {
    "task_start": 0,
    "task_end": int(time.time()),
    "wt_exists": False,
    "sickle_exists": False,
    "report_exists": False,
    "wt_mtime": 0,
    "sickle_mtime": 0,
    "report_mtime": 0,
    "wt_content": "",
    "sickle_content": "",
    "report_content": ""
}

try:
    with open("/tmp/task_start_time", "r") as f:
        res["task_start"] = int(f.read().strip())
except Exception:
    pass

wt_path = os.path.join(results_dir, "wt_hbb.fasta")
sickle_path = os.path.join(results_dir, "sickle_hbb.fasta")
report_path = os.path.join(results_dir, "charge_analysis_report.txt")

if os.path.exists(wt_path):
    res["wt_exists"] = True
    res["wt_mtime"] = int(os.path.getmtime(wt_path))
    with open(wt_path, "r", encoding="utf-8", errors="ignore") as f:
        res["wt_content"] = f.read()

if os.path.exists(sickle_path):
    res["sickle_exists"] = True
    res["sickle_mtime"] = int(os.path.getmtime(sickle_path))
    with open(sickle_path, "r", encoding="utf-8", errors="ignore") as f:
        res["sickle_content"] = f.read()

if os.path.exists(report_path):
    res["report_exists"] = True
    res["report_mtime"] = int(os.path.getmtime(report_path))
    with open(report_path, "r", encoding="utf-8", errors="ignore") as f:
        res["report_content"] = f.read()

with open("/tmp/task_result.json", "w") as f:
    json.dump(res, f)
PYEOF

# Ensure the verifier can read the json file across user boundaries
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Results exported to /tmp/task_result.json"
echo "=== Export complete ==="