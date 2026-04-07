#!/bin/bash
echo "=== Exporting maintenance_billing_code_reconciliation results ==="

source /workspace/scripts/task_utils.sh

# Final screenshot
take_screenshot /tmp/task_final.png

# Export data using Python
python3 << 'PYEOF'
import sys, json, os, re
sys.path.insert(0, "/workspace/scripts")
from cmdbuild_api import *

# Load baseline
baseline = load_baseline("/tmp/billing_reconcile_baseline.json")
if not baseline:
    print("Error: Baseline not found")
    sys.exit(0)

wo_type = baseline.get("wo_type")
wo_cls = baseline.get("wo_cls")
ids = baseline.get("ids", {})

token = get_token()
if not token:
    print("Error: Auth failed")
    sys.exit(0)

results = {}

for code, record_id in ids.items():
    record = get_record(wo_type, wo_cls, record_id, token)
    if record:
        notes = record.get("Notes", "")
        # Extract billing code if present
        match = re.search(r"BILLING_CODE:\s*([A-Z0-9-]+)", notes)
        billing_code = match.group(1) if match else None
        
        # Check modification info if available
        # CMDBuild often has UserUpdate and DateUpdate fields
        mod_user = record.get("UserUpdate")
        mod_date = record.get("DateUpdate") # often in timestamp format
        
        results[code] = {
            "notes": notes,
            "billing_code": billing_code,
            "exists": True,
            "mod_user": mod_user
        }
    else:
        results[code] = {"exists": False}

# Output to JSON
with open("/tmp/task_result.json", "w") as f:
    json.dump(results, f, indent=2)

print("Exported results to /tmp/task_result.json")
PYEOF

chmod 666 /tmp/task_result.json
echo "=== Export complete ==="