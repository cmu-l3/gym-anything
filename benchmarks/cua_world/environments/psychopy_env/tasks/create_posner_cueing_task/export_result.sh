#!/bin/bash
echo "=== Exporting Posner Cueing Task Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end.png

# Paths
EXP_FILE="/home/ga/PsychoPyExperiments/posner_cueing.psyexp"
COND_FILE="/home/ga/PsychoPyExperiments/posner_conditions.csv"

# Generate result JSON
python3 << 'PYEOF'
import json
import os
import sys
import datetime
import subprocess

EXP_FILE = "/home/ga/PsychoPyExperiments/posner_cueing.psyexp"
COND_FILE = "/home/ga/PsychoPyExperiments/posner_conditions.csv"
RESULT_FILE = "/tmp/posner_task_result.json"

results = {
    "exp_file_exists": False,
    "exp_file_modified": False,
    "exp_file_size": 0,
    "cond_file_exists": False,
    "cond_file_modified": False,
    "cond_file_size": 0,
    "psychopy_running": False,
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

# Check windows
try:
    wl = subprocess.run(["wmctrl", "-l"], capture_output=True, text=True, 
                        env={**os.environ, "DISPLAY": ":1"})
    results["windows"] = wl.stdout.replace("\n", " || ").strip()
except:
    pass

# Check PsychoPy running
try:
    ps = subprocess.run(["pgrep", "-f", "psychopy"], capture_output=True)
    results["psychopy_running"] = ps.returncode == 0
except:
    pass

# Check Experiment File
if os.path.isfile(EXP_FILE):
    results["exp_file_exists"] = True
    results["exp_file_size"] = os.path.getsize(EXP_FILE)
    mtime = int(os.path.getmtime(EXP_FILE))
    if mtime > results["task_start_time"]:
        results["exp_file_modified"] = True

# Check Conditions File
if os.path.isfile(COND_FILE):
    results["cond_file_exists"] = True
    results["cond_file_size"] = os.path.getsize(COND_FILE)
    mtime = int(os.path.getmtime(COND_FILE))
    if mtime > results["task_start_time"]:
        results["cond_file_modified"] = True

with open(RESULT_FILE, "w") as f:
    json.dump(results, f, indent=2)

os.chmod(RESULT_FILE, 0o666)
print(f"Result saved to {RESULT_FILE}")
PYEOF

cat /tmp/posner_task_result.json
echo "=== Export complete ==="