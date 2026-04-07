#!/bin/bash
echo "=== Exporting erp_asset_synchronization_protocol result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

python3 << 'PYEOF'
import sys, json, os
sys.path.insert(0, "/workspace/scripts")
from cmdbuild_api import *

# Load baseline
try:
    with open("/tmp/erp_baseline.json") as f:
        baseline = json.load(f)
except FileNotFoundError:
    print("Baseline not found")
    sys.exit(1)

token = get_token()
asset_cls = baseline["asset_class"]
ticket_cls = baseline["ticket_class"]
ticket_type = baseline["ticket_type"]
seeded_ids = baseline["seeded_ids"]

results = {}

# Check Asset States
for code, cid in seeded_ids.items():
    card = get_card(asset_cls, cid, token)
    results[code] = {
        "Description": card.get("Description", ""),
        "Status": card.get("Status", ""), # Raw status ID or Code
        "_is_active": card.get("_is_active"),
        "raw_card": card # Store for deep inspection if needed
    }
    
    # Try to resolve Status lookup description if possible
    status_val = card.get("Status")
    if isinstance(status_val, dict):
         results[code]["Status_Desc"] = status_val.get("description", "")
    else:
         results[code]["Status_Desc"] = str(status_val)

# Check for Safety Ticket
# We look for a ticket created AFTER the task started (roughly) 
# containing the trap serial number in description
trap_serial = baseline["trap_serial"]
found_tickets = []

if ticket_cls:
    # Get recent tickets
    tickets = get_records(ticket_type, ticket_cls, token, limit=20)
    for t in tickets:
        desc = t.get("Description", "") or ""
        if trap_serial in desc:
            found_tickets.append({
                "Description": desc,
                "Priority": t.get("Priority", "")
            })

results["tickets"] = found_tickets

with open("/tmp/erp_result.json", "w") as f:
    json.dump(results, f, indent=2, default=str)

PYEOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || true
cp /tmp/erp_result.json /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export complete ==="