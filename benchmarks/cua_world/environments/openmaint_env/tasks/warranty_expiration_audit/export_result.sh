#!/bin/bash
echo "=== Exporting warranty_expiration_audit result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/war_final_screenshot.png

# Run Python export script
python3 << 'PYEOF'
import sys, json, os, re
sys.path.insert(0, "/workspace/scripts")
from cmdbuild_api import *

baseline = load_baseline("/tmp/war_baseline.json")
if not baseline:
    print("ERROR: Baseline missing", file=sys.stderr)
    sys.exit(0)

token = get_token()
if not token:
    print("ERROR: Auth failed", file=sys.stderr)
    sys.exit(0)

asset_cls = baseline.get("asset_cls")
asset_ids = baseline.get("asset_ids", {})
desc_field = baseline.get("desc_field", "Description")
notes_field = baseline.get("notes_field", "Notes")
wo_type = baseline.get("wo_type")
wo_cls = baseline.get("wo_cls")

# 1. Fetch current state of seeded assets
assets_state = {}
for code, card_id in asset_ids.items():
    if not card_id:
        continue
    card = get_card(asset_cls, card_id, token)
    if card:
        assets_state[code] = {
            "Description": card.get(desc_field, ""),
            "Notes": card.get(notes_field, "") if notes_field != desc_field else card.get(desc_field, ""),
            "_is_active": card.get("_is_active", True)
        }
    else:
        assets_state[code] = {"missing": True}

# 2. Fetch all Work Orders created
# Since we don't know IDs, we fetch list. 
# We filter for ones that match our target codes in description or related fields.
target_wo_codes = ["WAR-GEN-001", "WAR-ELEC-003"]
found_wos = []

if wo_cls:
    # Get recent WOs
    wos = get_records(wo_type, wo_cls, token, limit=100)
    for wo in wos:
        # Check if created recently or relevant
        # Note: API might not easily give creation time in list, but we can filter by content
        desc = wo.get("Description", "") or ""
        code = wo.get("Code", "") or ""
        # Also check priority
        prio = wo.get("Priority", "")
        # Handle lookup for priority
        prio_val = ""
        if isinstance(prio, dict):
            prio_val = prio.get("description", "") or prio.get("code", "")
        else:
            prio_val = str(prio)
            
        # Check against targets
        for target in target_wo_codes:
            if target in desc or target in code:
                found_wos.append({
                    "id": wo.get("_id"),
                    "Code": code,
                    "Description": desc,
                    "Priority": prio_val,
                    "Target": target
                })

# 3. Compile Result
result = {
    "assets_state": assets_state,
    "found_wos": found_wos,
    "contam_initial": baseline.get("contam_initial")
}

with open("/tmp/war_result.json", "w") as f:
    json.dump(result, f, indent=2)

print("Exported JSON result.")
PYEOF

echo "=== Export complete ==="