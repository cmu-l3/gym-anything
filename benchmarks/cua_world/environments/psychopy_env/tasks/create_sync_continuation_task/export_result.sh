#!/bin/bash
echo "=== Exporting create_sync_continuation_task result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end.png

# Single Python call for basic file status and creating the result JSON
python3 << 'PYEOF'
import json
import os
import datetime
import subprocess

EXP_FILE = "/home/ga/PsychoPyExperiments/tapping/sync_continuation.psyexp"
COND_FILE = "/home/ga/PsychoPyExperiments/tapping/conditions.csv"
RESULT_FILE = "/tmp/create_sync_continuation_task_result.json"

results = {
    "exp_exists": False,
    "cond_exists": False,
    "exp_modified": False,
    "cond_modified": False,
    "task_start_time": 0,
    "result_nonce": "",
    "timestamp": datetime.datetime.now().isoformat(),
    "psychopy_running": False
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
    mtime = int(os.path.getmtime(EXP_FILE))
    if mtime > results["task_start_time"]:
        results["exp_modified"] = True

if os.path.isfile(COND_FILE):
    results["cond_exists"] = True
    mtime = int(os.path.getmtime(COND_FILE))
    if mtime > results["task_start_time"]:
        results["cond_modified"] = True

# Check App Status
try:
    ps = subprocess.run(["pgrep", "-f", "psychopy"], capture_output=True)
    results["psychopy_running"] = ps.returncode == 0
except:
    pass

with open(RESULT_FILE, "w") as f:
    json.dump(results, f, indent=2)

os.chmod(RESULT_FILE, 0o666)
print(f"Result saved to {RESULT_FILE}")
PYEOF

cat /tmp/create_sync_continuation_task_result.json
echo "=== Export complete ==="