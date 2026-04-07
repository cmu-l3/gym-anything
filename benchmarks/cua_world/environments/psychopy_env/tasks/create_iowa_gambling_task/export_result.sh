#!/bin/bash
echo "=== Exporting Iowa Gambling Task Result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end.png

# Paths
EXP_FILE="/home/ga/PsychoPyExperiments/iowa_gambling_task.psyexp"
CSV_FILE="/home/ga/PsychoPyExperiments/conditions/igt_decks.csv"
RESULT_FILE="/tmp/task_result.json"

# Python script to gather basic metadata and some content checks
# (Deep verification happens in verifier.py using copy_from_env)
python3 << PYEOF
import json
import os
import datetime
import sys

results = {
    "exp_file_exists": False,
    "csv_file_exists": False,
    "exp_mtime": 0,
    "csv_mtime": 0,
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

# Check files
if os.path.exists("$EXP_FILE"):
    results["exp_file_exists"] = True
    results["exp_mtime"] = int(os.path.getmtime("$EXP_FILE"))

if os.path.exists("$CSV_FILE"):
    results["csv_file_exists"] = True
    results["csv_mtime"] = int(os.path.getmtime("$CSV_FILE"))

# Write to JSON
with open("$RESULT_FILE", "w") as f:
    json.dump(results, f, indent=2)

os.chmod("$RESULT_FILE", 0o666)
print(f"Exported basic metadata to $RESULT_FILE")
PYEOF

echo "=== Export Complete ==="