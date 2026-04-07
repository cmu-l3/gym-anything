#!/bin/bash
echo "=== Exporting utility_meter_reading_log_and_anomaly_response result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

python3 << 'PYEOF'
import sys, json, os
sys.path.insert(0, "/workspace/scripts")
from cmdbuild_api import *

baseline = load_baseline("/tmp/meter_baseline.json")
if not baseline:
    with open("/tmp/meter_result.json", "w") as f:
        json.dump({"error": "baseline_missing"}, f)
    sys.exit(0)

token = get_token()
if not token:
    with open("/tmp/meter_result.json", "w") as f:
        json.dump({"error": "auth_failed"}, f)
    sys.exit(0)

asset_cls = baseline.get("asset_class")
wo_cls = baseline.get("wo_class")
wo_type = baseline.get("wo_type")
meter_ids = baseline.get("meter_ids", {})

# 1. Check Asset Descriptions (Readings Logged)
asset_states = {}
for code, cid in meter_ids.items():
    card = get_card(asset_cls, cid, token)
    desc = card.get("Description", "")
    asset_states[code] = {
        "id": cid,
        "description": desc,
        "description_lower": desc.lower()
    }

# 2. Check for New Work Orders
# We get all WOs and filter for those created "recently" or linked to our assets
# Since we don't have exact timestamps easily in this script context, 
# we'll look for WOs that reference our asset IDs and have "High" priority or specific text.

all_wos = get_records(wo_type, wo_cls, token, limit=200) if wo_cls else []

created_wos = []
for wo in all_wos:
    # Check link to asset
    # The reference field name varies. Usually 'Reference', 'Asset', 'CI', 'Equipment'
    # We inspect values to see if any match our meter IDs
    
    linked_asset = None
    wo_desc = wo.get("Description", "")
    wo_prio = ""
    
    # Extract priority
    p_val = wo.get("Priority")
    if isinstance(p_val, dict):
        wo_prio = (p_val.get("description") or p_val.get("code") or "").lower()
    else:
        wo_prio = str(p_val).lower() if p_val else ""

    # Check for linkage in all fields (robustness)
    for k, v in wo.items():
        val_id = ""
        if isinstance(v, dict):
            val_id = v.get("_id")
        elif isinstance(v, str):
            val_id = v
        
        if val_id in meter_ids.values():
            linked_asset = [code for code, mid in meter_ids.items() if mid == val_id][0]
            break
    
    # Fallback: Check if description contains the Asset Code (Agent might put it in text)
    if not linked_asset:
        for code in meter_ids.keys():
            if code in wo_desc:
                linked_asset = code
                break

    if linked_asset:
        created_wos.append({
            "id": wo.get("_id"),
            "asset_code": linked_asset,
            "description": wo_desc,
            "priority": wo_prio,
            "status": str(wo.get("Status", "")).lower()
        })
    else:
        # Capture WOs that might be relevant based on description text even if not linked
        if "high usage" in wo_desc.lower() or "leak" in wo_desc.lower():
             created_wos.append({
                "id": wo.get("_id"),
                "asset_code": "UNKNOWN",
                "description": wo_desc,
                "priority": wo_prio,
                "status": str(wo.get("Status", "")).lower()
            })

result = {
    "asset_states": asset_states,
    "created_wos": created_wos,
    "baseline_wo_count": baseline.get("initial_wo_count", 0),
    "current_wo_count": len(all_wos)
}

with open("/tmp/meter_result.json", "w") as f:
    json.dump(result, f, indent=2)

print("Result exported.")
PYEOF

echo "=== Export complete ==="