#!/bin/bash
echo "=== Exporting BMS Firmware Upgrade Result ==="

source /workspace/scripts/task_utils.sh

# 1. Capture final screenshot
take_screenshot /tmp/task_final.png

# 2. Run Python export script
python3 << 'PYEOF'
import sys, json, os, datetime
sys.path.insert(0, "/workspace/scripts")
from cmdbuild_api import *

# Load baseline
baseline = load_baseline("/tmp/bms_task_baseline.json")
if not baseline:
    print("Error: Baseline not found")
    sys.exit(0)

asset_cls = baseline.get("asset_class")
seeded_assets = baseline.get("seeded_assets", {})

token = get_token()
if not token:
    print("Error: Auth failed")
    sys.exit(0)

# Find Work Order Class (CorrectiveMaintenance, WorkOrder, or Ticket)
wo_type, wo_cls = find_maintenance_class(token)
print(f"Found Work Order Class: {wo_cls} ({wo_type})")

# Fetch all recent work orders
all_wos = get_records(wo_type, wo_cls, token, limit=100)
print(f"Fetched {len(all_wos)} work orders")

# Map of Asset ID -> List of Work Orders
asset_wo_map = {}

for wo in all_wos:
    # Check creation time to ensure it was created during task (simple filter if needed, 
    # but for now we rely on the specific CVE description)
    
    desc = wo.get("Description", "")
    prio_obj = wo.get("Priority", {})
    prio = str(prio_obj.get("code", prio_obj) if isinstance(prio_obj, dict) else prio_obj).lower()
    
    # Try to find related asset
    # The relation field name varies. Common ones: "RelatedAsset", "Reference", "CI", "Equipment"
    related_asset_id = None
    
    # Inspect attributes to find relation field if generic logic fails
    # But usually it comes in the payload if expanded. 
    # NOTE: The API helper `get_records` might not expand relations by default.
    # We might need to inspect the 'Reference' or specific fields.
    
    # Heuristic: iterate keys, look for dicts that look like asset references
    for key, val in wo.items():
        if isinstance(val, dict) and "_id" in val:
            # Check if this ID matches any of our seeded assets
            rid = val["_id"]
            for code, info in seeded_assets.items():
                if info["id"] == rid:
                    related_asset_id = rid
                    break
        if related_asset_id: break
    
    # If standard field knowledge is available
    if not related_asset_id:
        # try "Reference" field specifically
        ref = wo.get("Reference") or wo.get("RelatedAsset") or wo.get("Equipment")
        if ref:
            if isinstance(ref, dict): related_asset_id = ref.get("_id")
            else: related_asset_id = ref # raw ID

    if related_asset_id:
        if related_asset_id not in asset_wo_map:
            asset_wo_map[related_asset_id] = []
        
        asset_wo_map[related_asset_id].append({
            "id": wo.get("_id"),
            "description": desc,
            "priority": prio,
            "date": wo.get("PlannedDate") or wo.get("Date") or ""
        })

# Build Verification Result
results = {
    "eligible_assets": [],
    "ineligible_assets": [],
    "wos_created": 0,
    "correct_wos": 0,
    "incorrect_wos": 0
}

for code, info in seeded_assets.items():
    aid = info["id"]
    is_eligible = info["eligible"]
    linked_wos = asset_wo_map.get(aid, [])
    
    asset_result = {
        "code": code,
        "eligible": is_eligible,
        "wo_count": len(linked_wos),
        "wos": linked_wos
    }
    
    if is_eligible:
        results["eligible_assets"].append(asset_result)
        if len(linked_wos) > 0:
            results["correct_wos"] += 1
    else:
        results["ineligible_assets"].append(asset_result)
        if len(linked_wos) > 0:
            results["incorrect_wos"] += 1

results["wos_created"] = len(all_wos) # rough count

# Save to JSON
with open("/tmp/task_result.json", "w") as f:
    json.dump(results, f, indent=2)

print("Export completed.")
PYEOF

# Ensure permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export Complete ==="