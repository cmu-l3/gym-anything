#!/bin/bash
echo "=== Exporting N-Back Task Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end.png

# Paths
EXP_FILE="/home/ga/PsychoPyExperiments/nback_task.psyexp"
COND_FILE="/home/ga/PsychoPyExperiments/conditions/nback_conditions.csv"
RESULT_FILE="/tmp/task_result.json"

# Capture basic file stats in JSON (verifier will do deep analysis)
# We use python here to reliably generate JSON
python3 << PYEOF
import json
import os
import time

exp_path = "$EXP_FILE"
cond_path = "$COND_FILE"
result_path = "$RESULT_FILE"
start_time_file = "/home/ga/.task_start_time"
nonce_file = "/home/ga/.task_nonce"

data = {
    "timestamp": time.time(),
    "task_start_time": 0,
    "nonce": "",
    "exp_exists": False,
    "exp_mtime": 0,
    "exp_size": 0,
    "cond_exists": False,
    "cond_mtime": 0,
    "cond_size": 0,
    "screenshot_path": "/tmp/task_end.png"
}

# Read start time
if os.path.exists(start_time_file):
    with open(start_time_file) as f:
        try:
            data["task_start_time"] = int(f.read().strip())
        except:
            pass

# Read nonce
if os.path.exists(nonce_file):
    with open(nonce_file) as f:
        data["nonce"] = f.read().strip()

# Check experiment file
if os.path.exists(exp_path):
    data["exp_exists"] = True
    data["exp_mtime"] = int(os.path.getmtime(exp_path))
    data["exp_size"] = os.path.getsize(exp_path)

# Check conditions file
if os.path.exists(cond_path):
    data["cond_exists"] = True
    data["cond_mtime"] = int(os.path.getmtime(cond_path))
    data["cond_size"] = os.path.getsize(cond_path)

with open(result_path, "w") as f:
    json.dump(data, f, indent=2)

print(f"Exported basic stats to {result_path}")
PYEOF

# Set permissions so verifier can read
chmod 666 /tmp/task_result.json 2>/dev/null || true
if [ -f "$EXP_FILE" ]; then chmod 644 "$EXP_FILE"; fi
if [ -f "$COND_FILE" ]; then chmod 644 "$COND_FILE"; fi

cat /tmp/task_result.json
echo "=== Export complete ==="