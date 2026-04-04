#!/bin/bash
echo "=== Exporting multi_building_work_order_batch result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/wob_final_screenshot.png

python3 << 'PYEOF'
import sys, json, os
sys.path.insert(0, "/workspace/scripts")
from cmdbuild_api import *

baseline = load_baseline("/tmp/wob_baseline.json")
if not baseline:
    with open("/tmp/wob_result.json", "w") as f:
        json.dump({"error": "baseline_missing"}, f)
    sys.exit(0)

token = get_token()
if not token:
    with open("/tmp/wob_result.json", "w") as f:
        json.dump({"error": "auth_failed"}, f)
    sys.exit(0)

wo_type = baseline.get("wo_type")
wo_cls = baseline.get("wo_class")
priority_field = baseline.get("priority_field")
building_field = baseline.get("building_field")
status_field = baseline.get("status_field")
existing_ids = set(baseline.get("existing_ids", []))
expected_codes = baseline.get("expected_new_codes", [])
expected_specs = baseline.get("expected_new_specs", {})
pre_resolved_id = baseline.get("pre_resolved_id")
contam_id = baseline.get("contam_id")
buildings = baseline.get("buildings", [])

# Get all current WOs
all_wos = get_records(wo_type, wo_cls, token, limit=500) if wo_cls else []

# Find new storm work orders by code
new_wo_details = {}
for code in expected_codes:
    found = None
    for wo in all_wos:
        if wo.get("Code", "") == code:
            found = wo
            break
    if not found:
        # Also check among all non-baseline WOs
        for wo in all_wos:
            if wo.get("_id") not in existing_ids:
                desc = (wo.get("Description", "") or "").lower()
                spec = expected_specs.get(code, {})
                keywords = spec.get("desc_keywords", [])
                if any(kw in desc for kw in keywords):
                    found = wo
                    break

    if found:
        detail = {
            "found": True,
            "id": found.get("_id"),
            "code": found.get("Code", ""),
            "description": found.get("Description", ""),
        }
        # Priority
        if priority_field:
            pval = found.get(priority_field)
            if isinstance(pval, dict):
                detail["priority"] = (pval.get("description", "") or pval.get("code", "")).lower()
            else:
                detail["priority"] = str(pval).lower() if pval else ""
        else:
            detail["priority"] = ""
        # Building
        if building_field:
            bval = found.get(building_field)
            if isinstance(bval, dict):
                detail["building_id"] = bval.get("_id")
            elif bval:
                detail["building_id"] = bval
            else:
                detail["building_id"] = None
        else:
            detail["building_id"] = None
        new_wo_details[code] = detail
    else:
        new_wo_details[code] = {"found": False}

# Check pre-resolved WO status
pre_resolved_state = {}
if pre_resolved_id:
    card = get_record(wo_type, wo_cls, pre_resolved_id, token)
    if card:
        status_val = ""
        if status_field:
            sval = card.get(status_field)
            if isinstance(sval, dict):
                status_val = (sval.get("description", "") or sval.get("code", "")).lower()
            else:
                status_val = str(sval).lower() if sval else ""
        flow_status = str(card.get("_card_status", card.get("FlowStatus", ""))).lower()
        is_active = card.get("_is_active", True)
        closed_kw = ["closed", "completed", "resolved", "done", "finished"]
        is_closed = any(kw in status_val for kw in closed_kw) or \
                    any(kw in flow_status for kw in closed_kw) or \
                    is_active is False
        pre_resolved_state = {
            "exists": True,
            "status": status_val,
            "flow_status": flow_status,
            "is_active": is_active,
            "is_closed": is_closed,
        }
    else:
        pre_resolved_state = {"exists": False, "is_closed": True}

# Check contamination WO
contam_state = {}
if contam_id:
    card = get_record(wo_type, wo_cls, contam_id, token)
    if card:
        desc = card.get("Description", "")
        prio = ""
        if priority_field:
            pval = card.get(priority_field)
            if isinstance(pval, dict):
                prio = (pval.get("description", "") or pval.get("code", "")).lower()
            else:
                prio = str(pval).lower() if pval else ""
        is_active = card.get("_is_active", True)

        # Compare with initial state
        desc_unchanged = desc == baseline.get("contam_initial_desc", "")
        contam_state = {
            "exists": True,
            "is_active": is_active,
            "description": desc,
            "priority": prio,
            "description_unchanged": desc_unchanged,
            "preserved": is_active is not False and desc_unchanged,
        }
    else:
        contam_state = {"exists": False, "preserved": False}

result = {
    "wo_class": wo_cls,
    "new_wo_details": new_wo_details,
    "pre_resolved_state": pre_resolved_state,
    "contam_state": contam_state,
    "buildings": buildings,
    "expected_specs": expected_specs,
    "baseline_count": baseline.get("baseline_count", 0),
    "current_count": len(all_wos),
}

with open("/tmp/wob_result.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

print("Result saved to /tmp/wob_result.json")
print(json.dumps(result, indent=2, default=str))
PYEOF

echo "=== multi_building_work_order_batch export complete ==="
