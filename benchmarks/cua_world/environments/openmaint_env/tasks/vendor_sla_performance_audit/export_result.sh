#!/bin/bash
echo "=== Exporting Vendor SLA Audit Results ==="

source /workspace/scripts/task_utils.sh

# Capture Final Screenshot
take_screenshot /tmp/task_final.png

# Export Data via Python
python3 << 'PYEOF'
import sys, json, os
sys.path.insert(0, "/workspace/scripts")
from cmdbuild_api import *

# Load baseline to get IDs
baseline = load_baseline("/tmp/sla_baseline.json")
if not baseline:
    print("No baseline found!", file=sys.stderr)
    sys.exit(0)

token = get_token()
wo_cls = baseline.get("wo_cls")
wo_type = baseline.get("wo_type")
seeded_ids = baseline.get("seeded_ids", {})

results = {}

for code, rid in seeded_ids.items():
    if not rid:
        results[code] = {"error": "no_id"}
        continue
        
    record = get_record(wo_type, wo_cls, rid, token)
    if record:
        results[code] = {
            "Description": record.get("Description", ""),
            "ModifyUser": record.get("ModifyUser", ""), # To check if modified by user
            "ModifyDate": record.get("ModifyDate", "")  # To check timestamp
        }
    else:
        results[code] = {"error": "not_found"}

# Save to JSON
with open("/tmp/sla_audit_result.json", "w") as f:
    json.dump(results, f, indent=2)

print("Exported audit results to /tmp/sla_audit_result.json")
PYEOF

echo "=== Export Complete ==="