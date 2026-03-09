#!/bin/bash
echo "=== Exporting asset_inventory_reconciliation result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/air_final_screenshot.png

python3 << 'PYEOF'
import sys, json, os
sys.path.insert(0, "/workspace/scripts")
from cmdbuild_api import *

baseline = load_baseline("/tmp/air_baseline.json")
if not baseline:
    with open("/tmp/air_result.json", "w") as f:
        json.dump({"error": "baseline_missing"}, f)
    sys.exit(0)

token = get_token()
if not token:
    with open("/tmp/air_result.json", "w") as f:
        json.dump({"error": "auth_failed"}, f)
    sys.exit(0)

asset_cls = baseline.get("asset_class")
serial_field = baseline.get("serial_field")
building_field = baseline.get("building_field")
serial_fix_ids = baseline.get("serial_fix_ids", {})
serial_corrections = baseline.get("serial_corrections", {})
decom_ids = baseline.get("decom_ids", {})
contam_id = baseline.get("contam_id")
loc_fix_ids = baseline.get("loc_fix_ids", {})
loc_corrections = baseline.get("loc_corrections", {})
new_asset_codes = baseline.get("new_asset_codes", [])
buildings = baseline.get("buildings", [])

# Check serial number corrections
serial_results = {}
for code, card_id in serial_fix_ids.items():
    if not card_id:
        serial_results[code] = {"error": "no_id"}
        continue
    card = get_card(asset_cls, card_id, token)
    if not card:
        serial_results[code] = {"deleted": True}
        continue
    current_serial = ""
    if serial_field:
        current_serial = str(card.get(serial_field, "") or "")
    expected = serial_corrections.get(code, "")
    serial_results[code] = {
        "current_serial": current_serial,
        "expected_serial": expected,
        "is_correct": current_serial == expected,
    }

# Check decommissioned assets
decom_results = {}
for code, card_id in decom_ids.items():
    if not card_id:
        decom_results[code] = {"error": "no_id"}
        continue
    card = get_card(asset_cls, card_id, token)
    if not card:
        decom_results[code] = {"decommissioned": True, "method": "deleted"}
        continue
    is_active = card.get("_is_active", True)
    status_val = ""
    status_field = baseline.get("status_field")
    if status_field:
        sval = card.get(status_field)
        if isinstance(sval, dict):
            status_val = (sval.get("description", "") or sval.get("code", "")).lower()
        elif sval:
            status_val = str(sval).lower()
    decom_keywords = ["decommission", "retired", "disposed", "inactive", "removed",
                      "out of service", "obsolete"]
    is_decom = (not is_active) or any(kw in status_val for kw in decom_keywords)
    decom_results[code] = {
        "decommissioned": is_decom,
        "is_active": is_active,
        "status": status_val,
        "method": "status_change" if is_decom else "still_active",
    }

# Check contamination asset
contam_result = {"preserved": False}
if contam_id:
    card = get_card(asset_cls, contam_id, token)
    if card:
        is_active = card.get("_is_active", True)
        contam_result = {
            "preserved": is_active is not False,
            "is_active": is_active,
            "exists": True,
        }
    else:
        contam_result = {"preserved": False, "exists": False, "deleted": True}

# Check new assets created
all_cards = get_cards(asset_cls, token, limit=1000)
new_assets_found = {}
for code in new_asset_codes:
    found = False
    for card in all_cards:
        if card.get("Code", "") == code:
            found = True
            new_assets_found[code] = {
                "found": True,
                "id": card.get("_id"),
                "description": card.get("Description", ""),
                "serial": str(card.get(serial_field, "") or "") if serial_field else "",
            }
            break
    if not found:
        new_assets_found[code] = {"found": False}

# Check location corrections
loc_results = {}
for code, card_id in loc_fix_ids.items():
    if not card_id:
        loc_results[code] = {"error": "no_id"}
        continue
    card = get_card(asset_cls, card_id, token)
    if not card:
        loc_results[code] = {"deleted": True}
        continue
    current_building = None
    if building_field:
        bval = card.get(building_field)
        if isinstance(bval, dict):
            current_building = bval.get("_id")
        elif bval:
            current_building = bval
    expected_building = loc_corrections.get(code, {}).get("correct_building_id")
    loc_results[code] = {
        "current_building": current_building,
        "expected_building": expected_building,
        "is_correct": str(current_building) == str(expected_building) if current_building and expected_building else False,
    }

result = {
    "asset_class": asset_cls,
    "serial_results": serial_results,
    "decom_results": decom_results,
    "contam_result": contam_result,
    "new_assets_found": new_assets_found,
    "loc_results": loc_results,
    "baseline_count": baseline.get("baseline_count", 0),
    "current_count": len(all_cards),
}

with open("/tmp/air_result.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

print("Result saved to /tmp/air_result.json")
print(json.dumps(result, indent=2, default=str))
PYEOF

echo "=== asset_inventory_reconciliation export complete ==="
