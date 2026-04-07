#!/bin/bash
echo "=== Exporting build_gonogo_inhibition_task result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end.png

EXP_DIR="/home/ga/PsychoPyExperiments/go_nogo_task"
EXP_FILE="$EXP_DIR/go_nogo_task.psyexp"
CSV_FILE="$EXP_DIR/go_nogo_conditions.csv"
RESULT_FILE="/tmp/task_result.json"

# Python script to gather basic file stats and metadata
# We do mostly simple checks here; deep verification happens in verifier.py
python3 << PYEOF
import json
import os
import datetime
import subprocess

result = {
    "exp_dir_exists": False,
    "exp_file_exists": False,
    "csv_file_exists": False,
    "exp_file_mtime": 0,
    "csv_file_mtime": 0,
    "task_start_time": 0,
    "result_nonce": "",
    "timestamp": datetime.datetime.now().isoformat(),
    "psychopy_running": False
}

# Read task start time
try:
    with open("/home/ga/.task_start_time") as f:
        result["task_start_time"] = int(f.read().strip())
except:
    pass

# Read nonce
try:
    with open("/home/ga/.task_nonce") as f:
        result["result_nonce"] = f.read().strip()
except:
    pass

# Check directories and files
if os.path.isdir("$EXP_DIR"):
    result["exp_dir_exists"] = True

if os.path.isfile("$EXP_FILE"):
    result["exp_file_exists"] = True
    result["exp_file_mtime"] = int(os.path.getmtime("$EXP_FILE"))

if os.path.isfile("$CSV_FILE"):
    result["csv_file_exists"] = True
    result["csv_file_mtime"] = int(os.path.getmtime("$CSV_FILE"))

# Check if PsychoPy is running
try:
    ps = subprocess.run(["pgrep", "-f", "psychopy"], capture_output=True)
    result["psychopy_running"] = ps.returncode == 0
except:
    pass

with open("$RESULT_FILE", "w") as f:
    json.dump(result, f, indent=2)

os.chmod("$RESULT_FILE", 0o666)
PYEOF

cat "$RESULT_FILE"
echo "=== Export complete ==="