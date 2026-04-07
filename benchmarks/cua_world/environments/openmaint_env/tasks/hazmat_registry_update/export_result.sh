#!/bin/bash
echo "=== Exporting hazmat_registry_update result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Run Python export script
python3 << 'PYEOF'
import sys, json, os
sys.path.insert(0, "/workspace/scripts")
from cmdbuild_api import *

baseline = load_baseline("/tmp/hazmat_baseline.json")
if not baseline:
    print("ERROR: Baseline missing", file=sys.stderr)
    sys.exit(0)

token = get_token()
if not token:
    print("ERROR: Auth failed", file=sys.stderr)
    sys.exit(0)

asset_cls = baseline["asset_cls"]
room_cls = baseline["room_cls"]
room_ids = baseline["room_ids"]
haz1_id = baseline["haz1_id"]
room_notes_field = baseline["room_notes_field"]
asset_room_field = baseline["asset_room_field"]
asset_status_field = baseline["asset_status_field"]

# 1. Check HAZ-001 Status (Should be retired/inactive)
haz1_status = "unknown"
haz1_active = True
if haz1_id:
    card = get_card(asset_cls, haz1_id, token)
    if card:
        haz1_active = card.get("_is_active", True)
        raw_status = card.get(asset_status_field)
        if isinstance(raw_status, dict):
            haz1_status = raw_status.get("description", raw_status.get("code", "")).lower()
        else:
            haz1_status = str(raw_status).lower()
    else:
        haz1_status = "deleted"
        haz1_active = False

# 2. Check New Assets (HAZ-002, HAZ-003)
def check_asset(code, expected_room_id):
    cards = get_cards(asset_cls, token, limit=10, filter_str=f"filter={{\"attribute\":{{\"simple\":{{\"attribute\":\"Code\",\"operator\":\"equal\",\"value\":[\"{code}\"]}}}}}}")
    found = False
    correct_room = False
    desc_has_asbestos = False
    
    for c in cards:
        if c.get("_is_active", True): # Only check active cards
            found = True
            # Check Room
            loc = c.get(asset_room_field)
            loc_id = loc.get("_id") if isinstance(loc, dict) else loc
            if str(loc_id) == str(expected_room_id):
                correct_room = True
            
            # Check Description
            desc = c.get("Description", "").lower()
            if "asbestos" in desc:
                desc_has_asbestos = True
            break # Assume first match is the one
            
    return {"found": found, "correct_room": correct_room, "desc_has_asbestos": desc_has_asbestos}

haz2_result = check_asset("HAZ-002", room_ids.get("Boiler Room"))
haz3_result = check_asset("HAZ-003", room_ids.get("Roof Access"))

# 3. Check Trap (Office 102)
# Look for ANY asset in Office 102 with "Drywall" or "Asbestos" created recently
# Get assets in Office 102
office_id = room_ids.get("Office 102")
trap_triggered = False
if office_id:
    # We can't easily filter by "created recently" without parsing timestamps, so we check for suspicious content
    # Filter by Room not always easy via API string, so let's get all and filter in python if count is low, 
    # OR assume agent would name it sensibly or use keywords.
    # Let's search for "Drywall" or "Joint Compound" in description globally and check location
    candidates = get_cards(asset_cls, token, limit=50) # Assuming low total volume in test env, else rely on search
    for c in candidates:
        desc = c.get("Description", "").lower()
        loc = c.get(asset_room_field)
        loc_id = loc.get("_id") if isinstance(loc, dict) else loc
        
        if str(loc_id) == str(office_id):
             if any(x in desc for x in ["drywall", "compound", "haz", "asbestos"]):
                 trap_triggered = True

# 4. Check Room Warnings
def check_room_warning(room_name):
    rid = room_ids.get(room_name)
    if not rid: return False
    card = get_card(room_cls, rid, token)
    notes = card.get(room_notes_field, "") or ""
    desc = card.get("Description", "") or "" # Sometimes agents append to description
    target = "WARNING: HAZMAT PRESENT - 2026 SURVEY"
    return target in notes or target in desc

warning_boiler = check_room_warning("Boiler Room")
warning_roof = check_room_warning("Roof Access")

result = {
    "haz1": {
        "status": haz1_status,
        "active": haz1_active,
        "retired": (not haz1_active) or any(x in haz1_status for x in ["retired", "disposed", "inactive"])
    },
    "haz2": haz2_result,
    "haz3": haz3_result,
    "trap_triggered": trap_triggered,
    "warnings": {
        "boiler": warning_boiler,
        "roof": warning_roof
    }
}

with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f)

print("Export complete.")
PYEOF

chmod 666 /tmp/task_result.json 2>/dev/null || true
echo "=== Export complete ==="