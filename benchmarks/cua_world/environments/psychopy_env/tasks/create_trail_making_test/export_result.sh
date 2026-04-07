#!/bin/bash
echo "=== Exporting create_trail_making_test result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end.png

# We use Python to do a preliminary check and gather metadata
python3 << 'PYEOF'
import json
import os
import sys
import datetime
import subprocess

EXP_FILE = "/home/ga/PsychoPyExperiments/trail_making_test.psyexp"
COND_A = "/home/ga/PsychoPyExperiments/conditions/tmt_part_a.csv"
COND_B = "/home/ga/PsychoPyExperiments/conditions/tmt_part_b.csv"
RESULT_FILE = "/tmp/create_tmt_result.json"

results = {
    "exp_exists": False,
    "cond_a_exists": False,
    "cond_b_exists": False,
    "exp_modified": False,
    "task_start_time": 0,
    "result_nonce": "",
    "timestamp": datetime.datetime.now().isoformat(),
    # Detailed file stats for anti-gaming
    "exp_size": 0,
    "cond_a_lines": 0,
    "cond_b_lines": 0
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

# Check Experiment File
if os.path.isfile(EXP_FILE):
    results["exp_exists"] = True
    results["exp_size"] = os.path.getsize(EXP_FILE)
    mtime = int(os.path.getmtime(EXP_FILE))
    if mtime > results["task_start_time"]:
        results["exp_modified"] = True

# Check Conditions A
if os.path.isfile(COND_A):
    results["cond_a_exists"] = True
    with open(COND_A) as f:
        results["cond_a_lines"] = sum(1 for _ in f)

# Check Conditions B
if os.path.isfile(COND_B):
    results["cond_b_exists"] = True
    with open(COND_B) as f:
        results["cond_b_lines"] = sum(1 for _ in f)

with open(RESULT_FILE, "w") as f:
    json.dump(results, f, indent=2)

os.chmod(RESULT_FILE, 0o666)
print(f"Result metadata saved to {RESULT_FILE}")
PYEOF

cat /tmp/create_tmt_result.json
echo "=== Export complete ==="