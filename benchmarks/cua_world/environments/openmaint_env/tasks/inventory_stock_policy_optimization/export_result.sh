#!/bin/bash
echo "=== Exporting inventory_stock_policy_optimization result ==="

source /workspace/scripts/task_utils.sh

# Capture final screenshot
take_screenshot /tmp/task_final.png

# Run Python export script
python3 << 'PYEOF'
import sys, json, os, re
sys.path.insert(0, "/workspace/scripts")
from cmdbuild_api import *

# Load baseline
baseline = load_baseline("/tmp/inventory_baseline.json")
if not baseline:
    print("ERROR: Baseline not found", file=sys.stderr)
    sys.exit(0)

token = get_token()
if not token:
    print("ERROR: Auth failed", file=sys.stderr)
    sys.exit(0)

part_cls = baseline["part_class"]
min_field = baseline["min_field"]
max_field = baseline["max_field"]
seeded_ids = baseline["seeded_ids"]

# 1. Fetch Final State of Parts
parts_state = {}
for code, cid in seeded_ids.items():
    card = get_card(part_cls, cid, token)
    if not card:
        parts_state[code] = {"exists": False}
        continue
    
    parts_state[code] = {
        "exists": True,
        "is_active": card.get("_is_active", True),
        "status": str(card.get("Status", "")).lower(), # Assuming generic Status field exists or _is_active used
        "min": card.get(min_field),
        "max": card.get(max_field)
    }

# 2. Fetch Work Orders created during task
# Find WorkOrder class
wo_type, wo_cls = find_maintenance_class(token)
if not wo_cls:
    # Try generic "Activity" or "Request" if Maintenance not found
    wo_cls = find_process("Request", token) or find_class("Request", token)

new_wos = []
if wo_cls:
    # Get all WOs
    wos = get_records(wo_type, wo_cls, token, limit=100)
    
    # Filter for those created recently or matching description
    # Since we can't easily filter by creation time without specific fields, we look for key text
    for wo in wos:
        desc = (wo.get("Description", "") or "").lower()
        notes = (wo.get("Notes", "") or "").lower()
        code = wo.get("Code", "")
        
        # Check if it matches our task keywords
        if "procurement" in desc or "restock" in desc or "spares" in desc:
            new_wos.append({
                "code": code,
                "description": desc,
                "notes": notes,
                "category": str(wo.get("Category", "")),
                "priority": str(wo.get("Priority", ""))
            })

# 3. Construct Result
result = {
    "parts_state": parts_state,
    "work_orders": new_wos,
    "baseline": baseline
}

with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)

print("Result exported to /tmp/task_result.json")
PYEOF

chmod 666 /tmp/task_result.json 2>/dev/null || true
echo "=== Export complete ==="