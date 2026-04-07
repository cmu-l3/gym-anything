#!/bin/bash
echo "=== Exporting create_dms_memory_task result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end.png

# Paths
EXP_FILE="/home/ga/PsychoPyExperiments/dms_task.psyexp"
COND_FILE="/home/ga/PsychoPyExperiments/conditions/dms_conditions.csv"
RESULT_FILE="/tmp/dms_task_result.json"

# Python script to analyze the files and environment state
python3 << PYEOF
import json
import os
import sys
import datetime
import subprocess

result = {
    "exp_file_exists": False,
    "exp_file_size": 0,
    "exp_modified_time": 0,
    "cond_file_exists": False,
    "cond_file_size": 0,
    "cond_modified_time": 0,
    "task_start_time": 0,
    "result_nonce": "",
    "timestamp": datetime.datetime.now().isoformat()
}

# Load task start time
try:
    with open("/home/ga/.task_start_time") as f:
        result["task_start_time"] = int(f.read().strip())
except:
    pass

# Load nonce
try:
    with open("/home/ga/.task_nonce") as f:
        result["result_nonce"] = f.read().strip()
except:
    pass

# Check Experiment File
if os.path.exists("$EXP_FILE"):
    result["exp_file_exists"] = True
    result["exp_file_size"] = os.path.getsize("$EXP_FILE")
    result["exp_modified_time"] = os.path.getmtime("$EXP_FILE")

# Check Conditions File
if os.path.exists("$COND_FILE"):
    result["cond_file_exists"] = True
    result["cond_file_size"] = os.path.getsize("$COND_FILE")
    result["cond_modified_time"] = os.path.getmtime("$COND_FILE")

# Write to JSON
with open("$RESULT_FILE", "w") as f:
    json.dump(result, f, indent=2)

PYEOF

# Set permissions so verifier can read it (if copy_from_env uses specific user)
chmod 666 "$RESULT_FILE"

echo "Result exported to $RESULT_FILE"
cat "$RESULT_FILE"
echo "=== Export complete ==="