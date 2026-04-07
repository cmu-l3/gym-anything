#!/bin/bash
echo "=== Exporting weekend_incident_log_entry result ==="

source /workspace/scripts/task_utils.sh

# Capture final screenshot
take_screenshot /tmp/wsl_final_screenshot.png

# Run Python extraction
python3 << 'PYEOF'
import sys, json, os
sys.path.insert(0, "/workspace/scripts")
from cmdbuild_api import *

baseline = load_baseline("/tmp/wsl_baseline.json")
if not baseline:
    print("Error: No baseline found")
    sys.exit(0)

token = get_token()
if not token:
    print("Error: Auth failed")
    sys.exit(0)

ticket_type = baseline.get("ticket_type")
ticket_cls = baseline.get("ticket_cls")
pre_existing = set(baseline.get("pre_existing_ids", []))
p_field = baseline.get("priority_field")
b_field = baseline.get("building_field")

# Get all current tickets
all_tickets = get_records(ticket_type, ticket_cls, token, limit=200)

# Identify NEW tickets
new_tickets = []
for t in all_tickets:
    if t.get("_id") not in pre_existing:
        # Extract meaningful data
        p_val = t.get(p_field)
        if isinstance(p_val, dict):
            p_val = p_val.get("description", "") or p_val.get("code", "")
        
        b_val = t.get(b_field)
        b_id = b_val
        if isinstance(b_val, dict):
            b_id = b_val.get("_id")
            
        new_tickets.append({
            "id": t.get("_id"),
            "code": t.get("Code", ""),
            "description": t.get("Description", ""),
            "priority": str(p_val).lower(),
            "building_id": b_id
        })

# Export result
result = {
    "new_tickets": new_tickets,
    "baseline_map": baseline.get("building_map", {}),
    "ticket_class": ticket_cls
}

with open("/tmp/wsl_result.json", "w") as f:
    json.dump(result, f, indent=2)

print(f"Exported {len(new_tickets)} new tickets")
PYEOF

chmod 666 /tmp/wsl_result.json 2>/dev/null || true
echo "=== Export complete ==="