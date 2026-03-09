#!/bin/bash
echo "=== Exporting building_commissioning_data_entry result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/bcd_final_screenshot.png

python3 << 'PYEOF'
import sys, json, os
sys.path.insert(0, "/workspace/scripts")
from cmdbuild_api import *

baseline = load_baseline("/tmp/bcd_baseline.json")
if not baseline:
    with open("/tmp/bcd_result.json", "w") as f:
        json.dump({"error": "baseline_missing"}, f)
    sys.exit(0)

token = get_token()
if not token:
    with open("/tmp/bcd_result.json", "w") as f:
        json.dump({"error": "auth_failed"}, f)
    sys.exit(0)

building_cls = baseline.get("building_cls", "Building")
floor_cls = baseline.get("floor_cls", "Floor")
room_cls = baseline.get("room_cls", "Room")
asset_cls = baseline.get("asset_cls")
floor_building_field = baseline.get("floor_building_field")
room_floor_field = baseline.get("room_floor_field")
asset_building_field = baseline.get("asset_building_field")
asset_serial_field = baseline.get("asset_serial_field")

existing_building_ids = set(baseline.get("existing_building_ids", []))
existing_floor_ids = set(baseline.get("existing_floor_ids", []))
existing_room_ids = set(baseline.get("existing_room_ids", []))
existing_asset_ids = set(baseline.get("existing_asset_ids", []))

expected_building_code = baseline.get("expected_building_code", "BLD-WESTPARK")
expected_floor_codes = baseline.get("expected_floor_codes", [])
expected_room_codes = baseline.get("expected_room_codes", [])
expected_room_floors = baseline.get("expected_room_floors", {})
expected_asset_codes = baseline.get("expected_asset_codes", [])
expected_asset_serials = baseline.get("expected_asset_serials", {})

# Check building
all_buildings = get_cards(building_cls, token, limit=100)
building_found = None
for b in all_buildings:
    if b.get("Code", "") == expected_building_code:
        building_found = {
            "found": True,
            "id": b.get("_id"),
            "code": b.get("Code", ""),
            "description": b.get("Description", ""),
        }
        break
if not building_found:
    building_found = {"found": False}

# Check floors
all_floors = get_cards(floor_cls, token, limit=500)
floor_results = {}
floor_code_to_id = {}
for code in expected_floor_codes:
    found = False
    for f in all_floors:
        if f.get("Code", "") == code:
            found = True
            floor_id = f.get("_id")
            floor_code_to_id[code] = floor_id
            # Check building linkage
            building_ref = None
            if floor_building_field:
                bval = f.get(floor_building_field)
                if isinstance(bval, dict):
                    building_ref = bval.get("_id")
                elif bval:
                    building_ref = bval
            linked_to_building = False
            if building_found.get("found") and building_ref:
                linked_to_building = str(building_ref) == str(building_found["id"])
            floor_results[code] = {
                "found": True,
                "id": floor_id,
                "linked_to_building": linked_to_building,
            }
            break
    if not found:
        floor_results[code] = {"found": False}

# Check rooms
all_rooms = get_cards(room_cls, token, limit=1000)
room_results = {}
for code in expected_room_codes:
    found = False
    for r in all_rooms:
        if r.get("Code", "") == code:
            found = True
            room_id = r.get("_id")
            # Check floor linkage
            floor_ref = None
            if room_floor_field:
                fval = r.get(room_floor_field)
                if isinstance(fval, dict):
                    floor_ref = fval.get("_id")
                elif fval:
                    floor_ref = fval
            expected_floor_code = expected_room_floors.get(code, "")
            expected_floor_id = floor_code_to_id.get(expected_floor_code)
            linked_correctly = False
            if floor_ref and expected_floor_id:
                linked_correctly = str(floor_ref) == str(expected_floor_id)
            room_results[code] = {
                "found": True,
                "id": room_id,
                "description": r.get("Description", ""),
                "linked_to_correct_floor": linked_correctly,
            }
            break
    if not found:
        room_results[code] = {"found": False}

# Check assets
all_assets = get_cards(asset_cls, token, limit=1000) if asset_cls else []
asset_results = {}
for code in expected_asset_codes:
    found = False
    for a in all_assets:
        if a.get("Code", "") == code:
            found = True
            # Check serial
            current_serial = ""
            if asset_serial_field:
                current_serial = str(a.get(asset_serial_field, "") or "")
            expected_serial = expected_asset_serials.get(code, "")
            serial_correct = current_serial == expected_serial
            # Check building linkage
            building_ref = None
            if asset_building_field:
                bval = a.get(asset_building_field)
                if isinstance(bval, dict):
                    building_ref = bval.get("_id")
                elif bval:
                    building_ref = bval
            linked_to_building = False
            if building_found.get("found") and building_ref:
                linked_to_building = str(building_ref) == str(building_found["id"])
            asset_results[code] = {
                "found": True,
                "id": a.get("_id"),
                "serial_correct": serial_correct,
                "current_serial": current_serial,
                "expected_serial": expected_serial,
                "linked_to_building": linked_to_building,
            }
            break
    if not found:
        asset_results[code] = {"found": False}

# Check existing data preserved
current_building_ids = {b.get("_id") for b in all_buildings}
current_floor_ids = {f.get("_id") for f in all_floors}
current_room_ids = {r.get("_id") for r in all_rooms}
current_asset_ids = {a.get("_id") for a in all_assets}

buildings_preserved = len(existing_building_ids & current_building_ids)
floors_preserved = len(existing_floor_ids & current_floor_ids)
rooms_preserved = len(existing_room_ids & current_room_ids)
assets_preserved = len(existing_asset_ids & current_asset_ids)

result = {
    "building_found": building_found,
    "floor_results": floor_results,
    "room_results": room_results,
    "asset_results": asset_results,
    "preservation": {
        "buildings": {"preserved": buildings_preserved, "expected": len(existing_building_ids)},
        "floors": {"preserved": floors_preserved, "expected": len(existing_floor_ids)},
        "rooms": {"preserved": rooms_preserved, "expected": len(existing_room_ids)},
        "assets": {"preserved": assets_preserved, "expected": len(existing_asset_ids)},
    },
    "counts": {
        "buildings": len(all_buildings),
        "floors": len(all_floors),
        "rooms": len(all_rooms),
        "assets": len(all_assets),
    },
}

with open("/tmp/bcd_result.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

print("Result saved to /tmp/bcd_result.json")
print(json.dumps(result, indent=2, default=str))
PYEOF

echo "=== building_commissioning_data_entry export complete ==="
