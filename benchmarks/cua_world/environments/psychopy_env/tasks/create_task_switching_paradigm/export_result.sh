#!/bin/bash
echo "=== Exporting Task-Switching Paradigm result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end.png

# Paths
CSV_PATH="/home/ga/PsychoPyExperiments/conditions/task_switching_conditions.csv"
PSYEXP_PATH="/home/ga/PsychoPyExperiments/task_switching.psyexp"
RESULT_JSON="/tmp/task_result.json"

# Python script to gather basic metadata (deep verification happens in verifier.py)
python3 << PYEOF
import json
import os
import datetime

results = {
    "task_start_time": 0,
    "timestamp": datetime.datetime.now().isoformat(),
    "csv_exists": False,
    "csv_modified": False,
    "csv_size": 0,
    "psyexp_exists": False,
    "psyexp_modified": False,
    "psyexp_size": 0,
    "result_nonce": ""
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

# Check CSV
if os.path.exists("$CSV_PATH"):
    results["csv_exists"] = True
    results["csv_size"] = os.path.getsize("$CSV_PATH")
    if os.path.getmtime("$CSV_PATH") > results["task_start_time"]:
        results["csv_modified"] = True

# Check Psyexp
if os.path.exists("$PSYEXP_PATH"):
    results["psyexp_exists"] = True
    results["psyexp_size"] = os.path.getsize("$PSYEXP_PATH")
    if os.path.getmtime("$PSYEXP_PATH") > results["task_start_time"]:
        results["psyexp_modified"] = True

with open("$RESULT_JSON", "w") as f:
    json.dump(results, f, indent=2)
PYEOF

# Set permissions so verifier can copy it
chmod 666 "$RESULT_JSON" 2>/dev/null || true

echo "Export complete. Result summary:"
cat "$RESULT_JSON"