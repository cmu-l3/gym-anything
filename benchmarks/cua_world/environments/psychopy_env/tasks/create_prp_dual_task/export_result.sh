#!/bin/bash
echo "=== Exporting create_prp_dual_task result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end.png

# We will export a JSON summary of the file states to help the verifier,
# but the heavy lifting (XML parsing) is best done in the Python verifier
# to avoid dependency issues in shell.

python3 << 'PYEOF'
import json
import os
import datetime

CONDITIONS_FILE = "/home/ga/PsychoPyExperiments/prp_conditions.csv"
EXPERIMENT_FILE = "/home/ga/PsychoPyExperiments/prp_task.psyexp"
RESULT_FILE = "/tmp/create_prp_dual_task_result.json"

results = {
    "conditions_file_exists": False,
    "experiment_file_exists": False,
    "conditions_mtime": 0,
    "experiment_mtime": 0,
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

if os.path.exists(CONDITIONS_FILE):
    results["conditions_file_exists"] = True
    results["conditions_mtime"] = int(os.path.getmtime(CONDITIONS_FILE))

if os.path.exists(EXPERIMENT_FILE):
    results["experiment_file_exists"] = True
    results["experiment_mtime"] = int(os.path.getmtime(EXPERIMENT_FILE))

with open(RESULT_FILE, "w") as f:
    json.dump(results, f, indent=2)

os.chmod(RESULT_FILE, 0o666)
print(f"Result saved to {RESULT_FILE}")
PYEOF

cat /tmp/create_prp_dual_task_result.json
echo "=== Export complete ==="