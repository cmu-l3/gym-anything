#!/bin/bash
echo "=== Exporting GAD-7 Assessment Result ==="

source /workspace/scripts/task_utils.sh

# Capture final state screenshot
take_screenshot /tmp/task_end.png

# Paths
CSV_PATH="/home/ga/PsychoPyExperiments/gad7_items.csv"
EXP_PATH="/home/ga/PsychoPyExperiments/gad7_assessment.psyexp"
RESULT_JSON="/tmp/task_result.json"

# Python script to inspect files and generate result JSON
python3 << 'PYEOF'
import json
import os
import sys
import datetime
import subprocess

csv_path = "/home/ga/PsychoPyExperiments/gad7_items.csv"
exp_path = "/home/ga/PsychoPyExperiments/gad7_assessment.psyexp"
result_file = "/tmp/task_result.json"

results = {
    "timestamp": datetime.datetime.now().isoformat(),
    "csv_exists": False,
    "csv_modified": False,
    "exp_exists": False,
    "exp_modified": False,
    "task_start_time": 0,
    "result_nonce": "",
    "psychopy_running": False
}

# Read task start time
try:
    with open("/home/ga/.task_start_time") as f:
        results["task_start_time"] = int(f.read().strip())
except:
    pass

# Read nonce
try:
    with open("/home/ga/.task_nonce") as f:
        results["result_nonce"] = f.read().strip()
except:
    pass

# Check PsychoPy status
try:
    ps = subprocess.run(["pgrep", "-f", "psychopy"], capture_output=True)
    results["psychopy_running"] = ps.returncode == 0
except:
    pass

# Check CSV
if os.path.exists(csv_path):
    results["csv_exists"] = True
    mtime = int(os.path.getmtime(csv_path))
    if mtime > results["task_start_time"]:
        results["csv_modified"] = True

# Check Experiment File
if os.path.exists(exp_path):
    results["exp_exists"] = True
    mtime = int(os.path.getmtime(exp_path))
    if mtime > results["task_start_time"]:
        results["exp_modified"] = True

# Write result
with open(result_file, "w") as f:
    json.dump(results, f, indent=2)

os.chmod(result_file, 0o666)
PYEOF

echo "Result JSON generated at $RESULT_JSON"
cat $RESULT_JSON
echo "=== Export complete ==="