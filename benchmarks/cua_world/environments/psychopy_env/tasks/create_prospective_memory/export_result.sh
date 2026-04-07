#!/bin/bash
echo "=== Exporting create_prospective_memory result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end.png

# Paths
EXP_FILE="/home/ga/PsychoPyExperiments/prospective_memory.psyexp"
CSV_FILE="/home/ga/PsychoPyExperiments/conditions/pm_conditions.csv"
RESULT_FILE="/tmp/task_result.json"

# Collect file info using Python
python3 << PYEOF
import json
import os
import time

results = {
    "exp_exists": False,
    "csv_exists": False,
    "exp_mtime": 0,
    "csv_mtime": 0,
    "task_start_time": 0,
    "result_nonce": "",
    "timestamp": time.time()
}

# Read task start time
try:
    with open("/home/ga/.task_start_time", "r") as f:
        results["task_start_time"] = int(f.read().strip())
except:
    pass

# Read nonce
try:
    with open("/home/ga/.task_nonce", "r") as f:
        results["result_nonce"] = f.read().strip()
except:
    pass

# Check Experiment File
if os.path.isfile("$EXP_FILE"):
    results["exp_exists"] = True
    results["exp_mtime"] = int(os.path.getmtime("$EXP_FILE"))

# Check CSV File
if os.path.isfile("$CSV_FILE"):
    results["csv_exists"] = True
    results["csv_mtime"] = int(os.path.getmtime("$CSV_FILE"))

with open("$RESULT_FILE", "w") as f:
    json.dump(results, f, indent=2)

os.chmod("$RESULT_FILE", 0o666)
PYEOF

echo "Result metadata saved to $RESULT_FILE"
cat "$RESULT_FILE"
echo "=== Export complete ==="