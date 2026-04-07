#!/bin/bash
echo "=== Exporting create_method_of_adjustment_task result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end.png

# Single Python call for basic file analysis and JSON generation
python3 << 'PYEOF'
import json
import os
import sys
import datetime
import subprocess

EXP_FILE = "/home/ga/PsychoPyExperiments/size_matching.psyexp"
COND_FILE = "/home/ga/PsychoPyExperiments/conditions/size_conditions.csv"
RESULT_FILE = "/tmp/task_result.json"

results = {
    "exp_exists": False,
    "cond_exists": False,
    "exp_modified": False,
    "cond_modified": False,
    "task_start_time": 0,
    "result_nonce": "",
    "timestamp": datetime.datetime.now().isoformat(),
    "windows": ""
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

# Check files
if os.path.isfile(EXP_FILE):
    results["exp_exists"] = True
    if int(os.path.getmtime(EXP_FILE)) > results["task_start_time"]:
        results["exp_modified"] = True

if os.path.isfile(COND_FILE):
    results["cond_exists"] = True
    if int(os.path.getmtime(COND_FILE)) > results["task_start_time"]:
        results["cond_modified"] = True

# List windows for debugging
try:
    wl = subprocess.run(["wmctrl", "-l"], capture_output=True, text=True,
                        env={**os.environ, "DISPLAY": ":1"})
    results["windows"] = wl.stdout.replace("\n", " || ").strip()
except:
    pass

with open(RESULT_FILE, "w") as f:
    json.dump(results, f, indent=2)

os.chmod(RESULT_FILE, 0o666)
print(f"Result saved to {RESULT_FILE}")
PYEOF

cat /tmp/task_result.json
echo "=== Export complete ==="