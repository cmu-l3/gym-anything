#!/bin/bash
echo "=== Exporting create_sternberg_memory_search result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end.png

EXP_FILE="/home/ga/PsychoPyExperiments/sternberg_task.psyexp"
CSV_FILE="/home/ga/PsychoPyExperiments/sternberg_conditions.csv"
RESULT_FILE="/tmp/task_result.json"

# Python script to analyze the files in the container
# We do basic existence checks here, but deep logic verification happens in verifier.py
python3 << 'PYEOF'
import json
import os
import sys
import datetime

results = {
    "exp_exists": False,
    "csv_exists": False,
    "exp_size": 0,
    "csv_size": 0,
    "task_start_time": 0,
    "result_nonce": "",
    "timestamp": datetime.datetime.now().isoformat()
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

exp_path = "/home/ga/PsychoPyExperiments/sternberg_task.psyexp"
csv_path = "/home/ga/PsychoPyExperiments/sternberg_conditions.csv"

if os.path.isfile(exp_path):
    results["exp_exists"] = True
    results["exp_size"] = os.path.getsize(exp_path)

if os.path.isfile(csv_path):
    results["csv_exists"] = True
    results["csv_size"] = os.path.getsize(csv_path)

with open("/tmp/task_result.json", "w") as f:
    json.dump(results, f, indent=2)

os.chmod("/tmp/task_result.json", 0o666)
PYEOF

cat /tmp/task_result.json
echo "=== Export complete ==="