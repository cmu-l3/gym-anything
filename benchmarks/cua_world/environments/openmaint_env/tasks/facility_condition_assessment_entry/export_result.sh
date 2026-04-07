#!/bin/bash
echo "=== Exporting facility_condition_assessment_entry result ==="

source /workspace/scripts/task_utils.sh

# Timestamp anti-gaming
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Final screenshot
take_screenshot /tmp/task_final.png

# Python script to gather state
python3 << 'PYEOF'
import sys, json, os
sys.path.insert(0, "/workspace/scripts")
from cmdbuild_api import *

# Load baseline
try:
    with open("/tmp/fca_baseline.json", "r") as f:
        baseline = json.load(f)
except FileNotFoundError:
    print("Baseline not found", file=sys.stderr)
    sys.exit(0)

token = get_token()
if not token:
    print("Auth failed", file=sys.stderr)
    sys.exit(0)

asset_cls = baseline["asset_class"]
wo_cls = baseline["wo_class"]
wo_type = baseline["wo_type"]
asset_ids = baseline["asset_ids"]

results = {
    "assets": {},
    "work_orders": []
}

# 1. Check Asset States (Notes/Description updates)
print("Checking assets...")
for code, card_id in asset_ids.items():
    card = get_card(asset_cls, card_id, token)
    if card:
        # Check both Notes and Description as agent might append to either
        notes = card.get("Notes", "") or ""
        desc = card.get("Description", "") or ""
        results["assets"][code] = {
            "id": card_id,
            "notes": notes,
            "description": desc,
            "full_text": f"{desc} {notes}"
        }

# 2. Check for Work Orders
print(f"Checking Work Orders in {wo_cls}...")
# Fetch recent WOs
wos = get_records(wo_type, wo_cls, token, limit=100)

for wo in wos:
    # We are looking for WOs created during the task
    # Check if they reference our target assets
    
    wo_desc = wo.get("Description", "") or ""
    wo_prio = wo.get("Priority", "")
    if isinstance(wo_prio, dict):
        wo_prio = wo_prio.get("description", "") or wo_prio.get("code", "")
    
    # Check for direct reference linkage if possible
    # This depends on the specific schema, but usually there's a reference field.
    # We will search the WO data for the asset IDs.
    
    linked_asset_code = None
    
    # Heuristic 1: Check description for asset code
    for code in asset_ids.keys():
        if code in wo_desc:
            linked_asset_code = code
            break
            
    # Heuristic 2: Check all fields for the asset ID (reference)
    if not linked_asset_code:
        for key, val in wo.items():
            if isinstance(val, dict) and "_id" in val:
                # This is a reference
                ref_id = val["_id"]
                for code, aid in asset_ids.items():
                    if str(ref_id) == str(aid):
                        linked_asset_code = code
                        break
            if linked_asset_code: break
            
            # Simple ID match
            if str(val) in asset_ids.values():
                for code, aid in asset_ids.items():
                    if str(val) == str(aid):
                        linked_asset_code = code
                        break
            if linked_asset_code: break

    if linked_asset_code:
        results["work_orders"].append({
            "id": wo.get("_id"),
            "code": wo.get("Code", ""),
            "description": wo_desc,
            "priority": str(wo_prio).lower(),
            "linked_asset": linked_asset_code
        })

# Save results
with open("/tmp/task_result.json", "w") as f:
    json.dump(results, f, indent=2)

print("Export complete.")
PYEOF

echo "=== Export complete ==="