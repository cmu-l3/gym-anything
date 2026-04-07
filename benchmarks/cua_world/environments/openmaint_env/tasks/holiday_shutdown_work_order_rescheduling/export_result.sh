#!/bin/bash
echo "=== Exporting holiday_shutdown_work_order_rescheduling result ==="

source /workspace/scripts/task_utils.sh

# Capture final screenshot
take_screenshot /tmp/task_final.png

# Run Python export logic
python3 << 'PYEOF'
import sys, json, os
sys.path.insert(0, "/workspace/scripts")
from cmdbuild_api import *

# Load baseline
baseline = load_baseline("/tmp/shutdown_task_baseline.json")
if not baseline:
    print("ERROR: Baseline missing")
    sys.exit(0)

token = get_token()
wo_type = baseline.get("wo_type")
wo_cls = baseline.get("wo_cls")
date_field = baseline.get("date_field")
created_ids = baseline.get("created_ids", {})

results = {}

for code, rid in created_ids.items():
    if not rid:
        continue
    
    record = get_record(wo_type, wo_cls, rid, token)
    if not record:
        results[code] = "MISSING"
        continue
        
    # Extract relevant fields
    # Date might be returned as long timestamp or string
    raw_date = record.get(date_field)
    
    # Description/Notes
    desc = record.get("Description", "")
    notes = record.get("Notes", "")
    
    results[code] = {
        "date": raw_date,
        "description": desc,
        "notes": notes,
        "all_text": (str(desc) + " " + str(notes)).upper()
    }

# Save results
with open("/tmp/task_result.json", "w") as f:
    json.dump(results, f, indent=2, default=str)

print("Exported results to /tmp/task_result.json")
PYEOF

echo "=== Export complete ==="