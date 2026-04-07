#!/bin/bash
echo "=== Exporting emergency_evacuation_plan_update result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

python3 << 'PYEOF'
import sys, json, os
sys.path.insert(0, "/workspace/scripts")
from cmdbuild_api import *

baseline = load_baseline("/tmp/evac_baseline.json")
if not baseline:
    with open("/tmp/task_result.json", "w") as f:
        json.dump({"error": "baseline_missing"}, f)
    sys.exit(0)

token = get_token()
if not token:
    with open("/tmp/task_result.json", "w") as f:
        json.dump({"error": "auth_failed"}, f)
    sys.exit(0)

bld_cls = baseline.get("building_class")
ids = baseline.get("ids", {})

results = {}

for name, card_id in ids.items():
    if not card_id:
        results[name] = {"error": "no_id"}
        continue
        
    # Get Attachments
    resp = api("GET", f"classes/{bld_cls}/cards/{card_id}/attachments", token)
    attachments = []
    if resp and "data" in resp:
        for att in resp["data"]:
            attachments.append({
                "filename": att.get("FileName", ""),
                "description": att.get("Description", ""),
                "date": att.get("BeginDate", "") 
            })
    
    # Get Card Details (to verify status wasn't changed inappropriately)
    card = get_card(bld_cls, card_id, token)
    notes = card.get("Notes", "")
    
    results[name] = {
        "attachments": attachments,
        "notes": notes,
        "attachment_count": len(attachments)
    }

final_output = {
    "buildings": results,
    "baseline_ids": ids
}

with open("/tmp/task_result.json", "w") as f:
    json.dump(final_output, f, indent=2)

print("Exported JSON result.")
PYEOF

echo "=== Export complete ==="