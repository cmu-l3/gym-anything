#!/bin/bash
echo "=== Exporting preventive_maintenance_schedule_setup result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/pm_final_screenshot.png

python3 << 'PYEOF'
import sys, json, os, re
sys.path.insert(0, "/workspace/scripts")
from cmdbuild_api import *

baseline = load_baseline("/tmp/pm_baseline.json")
if not baseline:
    with open("/tmp/pm_result.json", "w") as f:
        json.dump({"error": "baseline_missing"}, f)
    sys.exit(0)

token = get_token()
if not token:
    with open("/tmp/pm_result.json", "w") as f:
        json.dump({"error": "auth_failed"}, f)
    sys.exit(0)

pm_type = baseline.get("pm_type")
pm_cls = baseline.get("pm_class")
existing_pm_ids = set(baseline.get("existing_pm_ids", []))
buildings = baseline.get("buildings", [])
building_field = baseline.get("building_field")
frequency_field = baseline.get("frequency_field")
priority_field = baseline.get("priority_field")
notes_field = baseline.get("notes_field")

# Get all current PM records (cards or process instances)
all_pms = get_records(pm_type, pm_cls, token, limit=500) if pm_cls else []

# Identify NEW PM cards (not in baseline)
new_pms = []
for pm in all_pms:
    if pm.get("_id") not in existing_pm_ids:
        new_pms.append(pm)

print(f"Found {len(new_pms)} new PM activities (total: {len(all_pms)}, baseline: {len(existing_pm_ids)})")

# Analyze each new PM
new_pm_details = []
for pm in new_pms:
    detail = {
        "id": pm.get("_id"),
        "code": pm.get("Code", ""),
        "description": pm.get("Description", ""),
    }

    # Read building reference
    if building_field:
        bval = pm.get(building_field)
        if isinstance(bval, dict):
            detail["building_id"] = bval.get("_id")
            detail["building_desc"] = bval.get("description", "")
        elif bval:
            detail["building_id"] = bval
            detail["building_desc"] = ""
        else:
            detail["building_id"] = None
            detail["building_desc"] = ""

    # Read frequency
    if frequency_field:
        fval = pm.get(frequency_field)
        if isinstance(fval, dict):
            detail["frequency"] = fval.get("description", str(fval))
        else:
            detail["frequency"] = str(fval) if fval else ""
    else:
        detail["frequency"] = ""

    # Read priority
    if priority_field:
        pval = pm.get(priority_field)
        if isinstance(pval, dict):
            detail["priority"] = (pval.get("description", "") or pval.get("code", "")).lower()
        else:
            detail["priority"] = str(pval).lower() if pval else ""
    else:
        detail["priority"] = ""

    # Read notes/checklist
    if notes_field:
        nval = pm.get(notes_field, "")
        detail["notes"] = str(nval) if nval else ""
    else:
        detail["notes"] = ""

    # Also check Description for task items
    full_text = (detail.get("description", "") + " " + detail.get("notes", "")).lower()
    task_items_found = []
    for item in ["filter", "coil", "refrigerant", "thermostat", "condensate"]:
        if item in full_text:
            task_items_found.append(item)
    detail["task_items_found"] = task_items_found

    # Check if code matches expected pattern PM-HVAC-Q-*
    detail["code_matches_pattern"] = bool(re.match(r"PM-HVAC-Q-", detail["code"], re.IGNORECASE))

    new_pm_details.append(detail)

# Check if existing PMs are still intact
existing_still_present = 0
for pm in all_pms:
    if pm.get("_id") in existing_pm_ids:
        existing_still_present += 1

# Build building ID set for matching
building_id_set = {b["id"] for b in buildings if b.get("id")}

result = {
    "pm_class": pm_cls,
    "baseline_pm_count": baseline.get("baseline_pm_count", 0),
    "current_pm_count": len(all_pms),
    "new_pm_count": len(new_pms),
    "new_pm_details": new_pm_details,
    "existing_preserved_count": existing_still_present,
    "expected_existing_count": len(existing_pm_ids),
    "buildings": buildings,
    "building_ids": list(building_id_set),
}

with open("/tmp/pm_result.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

print("Result saved to /tmp/pm_result.json")
print(json.dumps(result, indent=2, default=str))
PYEOF

echo "=== preventive_maintenance_schedule_setup export complete ==="
