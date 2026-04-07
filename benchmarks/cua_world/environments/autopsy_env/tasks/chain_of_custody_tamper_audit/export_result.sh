#!/bin/bash
# Export script for chain_of_custody_tamper_audit task

echo "=== Exporting results for chain_of_custody_tamper_audit ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final_state.png

# Kill Autopsy to ensure DB writes are flushed and lock is released
kill_autopsy
sleep 3

python3 << 'PYEOF'
import json
import os
import glob

result = {
    "task": "chain_of_custody_tamper_audit",
    "case_db_found": False,
    "report_exists": False,
    "report_mtime": 0,
    "report_content": "",
    "start_time": 0
}

# Read start time
try:
    with open("/tmp/chain_of_custody_start_time") as f:
        result["start_time"] = int(f.read().strip())
except Exception:
    pass

# Locate autopsy.db to confirm case creation
db_paths = glob.glob("/home/ga/Cases/Evidence_Audit_2024*/autopsy.db")
if db_paths:
    result["case_db_found"] = True

# Read the agent's report file
report_path = "/home/ga/Reports/integrity_audit.txt"
if os.path.exists(report_path):
    result["report_exists"] = True
    result["report_mtime"] = int(os.path.getmtime(report_path))
    with open(report_path, "r", errors="replace") as f:
        result["report_content"] = f.read(4096)

# Write to result JSON
with open("/tmp/chain_of_custody_result.json", "w") as f:
    json.dump(result, f, indent=2)
print("Result written to /tmp/chain_of_custody_result.json")
PYEOF

echo "=== Export complete ==="