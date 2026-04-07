#!/bin/bash
echo "=== Exporting spatial_hierarchy_remediation result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Run Python script to query API and generate result JSON
python3 << 'PYEOF'
import sys, json, os
sys.path.insert(0, "/workspace/scripts")
from cmdbuild_api import *

# Load Baseline
try:
    with open("/tmp/shr_baseline.json", "r") as f:
        baseline = json.load(f)
except Exception as e:
    print(f"ERROR: Could not load baseline: {e}", file=sys.stderr)
    sys.exit(0) # Exit cleanly so we don't crash export, verification will handle empty result

token = get_token()
if not token:
    print("ERROR: Could not authenticate", file=sys.stderr)
    sys.exit(0)

ids = baseline["ids"]
cls_names = baseline["classes"]
ref_fields = baseline["ref_fields"]

results = {
    "buildings": {},
    "floors": {},
    "rooms": {}
}

# 1. Check Buildings
for code, bid in ids["buildings"].items():
    card = get_card(cls_names["building"], bid, token)
    if card:
        results["buildings"][code] = {
            "exists": True,
            "Address": card.get("Address", ""),
            "City": card.get("City", "")
        }
    else:
        results["buildings"][code] = {"exists": False}

# 2. Check Floors
for code, fid in ids["floors"].items():
    card = get_card(cls_names["floor"], fid, token)
    if card:
        # Get parent building ID
        parent_ref = card.get(ref_fields["floor_to_building"])
        parent_id = None
        if isinstance(parent_ref, dict):
            parent_id = parent_ref.get("_id")
        elif parent_ref:
            parent_id = str(parent_ref)
        
        results["floors"][code] = {
            "exists": True,
            "parent_building_id": parent_id
        }
    else:
        results["floors"][code] = {"exists": False}

# 3. Check Rooms
for code, rid in ids["rooms"].items():
    card = get_card(cls_names["room"], rid, token)
    # Check if deleted (API returns empty or error usually, helper returns {})
    if not card or not card.get("_id"):
        results["rooms"][code] = {"exists": False, "active": False}
    else:
        # Get parent floor ID
        parent_ref = card.get(ref_fields["room_to_floor"])
        parent_id = None
        if isinstance(parent_ref, dict):
            parent_id = parent_ref.get("_id")
        elif parent_ref:
            parent_id = str(parent_ref)

        results["rooms"][code] = {
            "exists": True,
            "active": card.get("_is_active", True), # Check if deactivated
            "Description": card.get("Description", ""),
            "parent_floor_id": parent_id
        }

# Combine with expected data from baseline for verifier context
final_export = {
    "current_state": results,
    "baseline_config": baseline # Includes expected IDs and corrections
}

with open("/tmp/task_result.json", "w") as f:
    json.dump(final_export, f, indent=2)

print("Exported task_result.json")
PYEOF

echo "=== Export complete ==="