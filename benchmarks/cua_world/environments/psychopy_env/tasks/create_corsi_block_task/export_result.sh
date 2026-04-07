#!/bin/bash
echo "=== Exporting Corsi Block-Tapping Task Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Paths
SCRIPT_PATH="/home/ga/PsychoPyExperiments/corsi_task.py"
CSV_PATH="/home/ga/PsychoPyExperiments/conditions/corsi_sequences.csv"
RESULT_FILE="/tmp/task_result.json"

# Capture file stats using Python to ensure JSON validity
python3 << PYEOF
import json
import os
import sys
import datetime

results = {
    "script_exists": False,
    "script_size": 0,
    "script_mtime": 0,
    "csv_exists": False,
    "csv_size": 0,
    "csv_mtime": 0,
    "task_start_time": 0,
    "timestamp": datetime.datetime.now().isoformat()
}

# Read task start time
try:
    with open("/home/ga/.task_start_time") as f:
        results["task_start_time"] = int(f.read().strip())
except:
    pass

# Script stats
if os.path.exists("$SCRIPT_PATH"):
    results["script_exists"] = True
    results["script_size"] = os.path.getsize("$SCRIPT_PATH")
    results["script_mtime"] = int(os.path.getmtime("$SCRIPT_PATH"))

# CSV stats
if os.path.exists("$CSV_PATH"):
    results["csv_exists"] = True
    results["csv_size"] = os.path.getsize("$CSV_PATH")
    results["csv_mtime"] = int(os.path.getmtime("$CSV_PATH"))

with open("$RESULT_FILE", "w") as f:
    json.dump(results, f)

PYEOF

# Fix permissions
chmod 666 "$RESULT_FILE"

echo "Result exported to $RESULT_FILE"
cat "$RESULT_FILE"
echo "=== Export complete ==="