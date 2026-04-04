#!/bin/bash
set -e
echo "=== Setting up multi_building_work_order_batch ==="

source /workspace/scripts/task_utils.sh

if ! wait_for_openmaint 240; then
    echo "ERROR: OpenMaint is not reachable"
    exit 1
fi

python3 << 'PYEOF'
import sys, json, os
sys.path.insert(0, "/workspace/scripts")
from cmdbuild_api import *

token = get_token()
if not token:
    print("ERROR: Could not authenticate", file=sys.stderr)
    sys.exit(1)

print("Authenticated to CMDBuild API")

# Find the work order / corrective maintenance class (process-aware)
wo_type, wo_cls = find_maintenance_class(token)
print(f"Work order class: {wo_cls} (type={wo_type})")

# Get attributes
attrs = get_record_attributes(wo_type, wo_cls, token) if wo_cls else []
attr_map = {a.get("_id", ""): a for a in attrs}
print(f"WO attributes: {list(attr_map.keys())[:30]}")

# Discover fields
priority_field = None
building_field = None
status_field = None
category_field = None

for aname, ainfo in attr_map.items():
    alow = aname.lower()
    adesc = (ainfo.get("description", "") or "").lower()
    if "priority" in alow or "priority" in adesc:
        if not priority_field: priority_field = aname
    if "building" in alow or "location" in alow or "site" in alow:
        if not building_field: building_field = aname
    if "status" in alow and "flow" not in alow:
        if not status_field: status_field = aname
    if "category" in alow or "type" in alow and "class" not in alow:
        if not category_field: category_field = aname

print(f"Fields: priority={priority_field}, building={building_field}, "
      f"status={status_field}, category={category_field}")

# Get buildings
buildings = get_buildings(token)
bld_info = []
for b in buildings[:3]:
    bld_info.append({"id": b.get("_id"), "code": b.get("Code", ""), "desc": b.get("Description", "")})

print(f"Buildings: {json.dumps(bld_info)}")

# Create the pre-existing resolved work order (agent must close it)
pre_resolved_data = {
    "Code": "WO-PRE-RESOLVED",
    "Description": "Minor door hinge squeaking in reception - already fixed by on-site staff",
}
if priority_field:
    pre_resolved_data[priority_field] = "low"
if building_field and bld_info:
    pre_resolved_data[building_field] = bld_info[0]["id"]
pre_resolved_id = create_record(wo_type, wo_cls, pre_resolved_data, token)
print(f"Created pre-resolved WO: id={pre_resolved_id}")

# Create contamination work order (must NOT be modified)
contam_data = {
    "Code": "WO-CONTAM-001",
    "Description": "Quarterly fire extinguisher inspection - Building maintenance campaign FY2026-Q1",
}
if priority_field:
    contam_data[priority_field] = "medium"
if building_field and len(bld_info) > 1:
    contam_data[building_field] = bld_info[1]["id"]
contam_id = create_record(wo_type, wo_cls, contam_data, token)
print(f"Created contamination WO: id={contam_id}")

# Record contamination card's initial state for comparison
contam_initial = get_record(wo_type, wo_cls, contam_id, token) if contam_id else {}
contam_initial_desc = contam_initial.get("Description", "")
contam_initial_priority = ""
if priority_field and contam_initial:
    pval = contam_initial.get(priority_field)
    if isinstance(pval, dict):
        contam_initial_priority = pval.get("description", str(pval.get("_id", "")))
    else:
        contam_initial_priority = str(pval) if pval else ""

# Record baseline
baseline_count = count_records(wo_type, wo_cls, token) if wo_cls else 0
existing_wos = get_records(wo_type, wo_cls, token, limit=500)
existing_ids = [w.get("_id") for w in existing_wos]

baseline = {
    "wo_type": wo_type,
    "wo_class": wo_cls,
    "priority_field": priority_field,
    "building_field": building_field,
    "status_field": status_field,
    "category_field": category_field,
    "buildings": bld_info,
    "baseline_count": baseline_count,
    "existing_ids": existing_ids,
    "pre_resolved_id": pre_resolved_id,
    "contam_id": contam_id,
    "contam_initial_desc": contam_initial_desc,
    "contam_initial_priority": contam_initial_priority,
    "expected_new_codes": ["WO-STORM-001", "WO-STORM-002", "WO-STORM-003"],
    "expected_new_specs": {
        "WO-STORM-001": {
            "priority": "critical",
            "building_idx": 0,
            "desc_keywords": ["roof", "water", "intrusion"],
        },
        "WO-STORM-002": {
            "priority": "high",
            "building_idx": 1,
            "desc_keywords": ["hvac", "condenser", "rooftop"],
        },
        "WO-STORM-003": {
            "priority": "medium",
            "building_idx": 2,
            "desc_keywords": ["parking", "lighting", "garage"],
        },
    },
}
save_baseline("/tmp/wob_baseline.json", baseline)
print("Baseline saved to /tmp/wob_baseline.json")

# Create storm damage report on desktop
bld_names = [b.get("desc", b.get("code", f"Building {i+1}")) for i, b in enumerate(bld_info)]
report = f"""=== STORM DAMAGE ASSESSMENT REPORT ===
Date: 2026-03-06 06:00 AM
Event: Severe thunderstorm with 70mph gusts, heavy rain, lightning

BUILDING 1: {bld_names[0] if bld_names else 'Building 1'}
  Damage: Roof membrane breach on NW corner
  Impact: Active water intrusion into 4th floor electrical room
  Priority: CRITICAL — immediate risk of electrical short/fire
  Work Order Code: WO-STORM-001

BUILDING 2: {bld_names[1] if len(bld_names) > 1 else 'Building 2'}
  Damage: Rooftop HVAC unit displaced by wind
  Impact: Condenser fan housing cracked, unit non-operational
  Priority: HIGH — building HVAC compromised, tenant comfort affected
  Work Order Code: WO-STORM-002

BUILDING 3: {bld_names[2] if len(bld_names) > 2 else 'Building 3'}
  Damage: Parking garage lighting circuit tripped
  Impact: 60% of B1 level lights out after power surge
  Priority: MEDIUM — safety concern but garage still accessible
  Work Order Code: WO-STORM-003

ADDITIONAL NOTES:
- Work order WO-PRE-RESOLVED (minor door hinge issue) was already
  fixed by night shift staff. Please close this work order.
- Work order WO-CONTAM-001 is part of the quarterly fire extinguisher
  campaign — DO NOT modify it. It is unrelated to storm damage.
"""

with open("/home/ga/Desktop/storm_damage_report.txt", "w") as f:
    f.write(report)
os.chmod("/home/ga/Desktop/storm_damage_report.txt", 0o666)
print("Storm damage report created")
PYEOF

date +%s > /tmp/wob_start_ts

# Restart browser
pkill -f firefox || true
sleep 1
su - ga -c "DISPLAY=:1 firefox '$OPENMAINT_URL' > /tmp/firefox_task_wob.log 2>&1 &"

if ! wait_for_window "firefox|mozilla|openmaint|cmdbuild" 40; then
    echo "WARNING: Firefox window not detected"
fi
focus_firefox || true
su - ga -c "DISPLAY=:1 xdotool key ctrl+l"
sleep 0.3
su - ga -c "DISPLAY=:1 xdotool type --delay 20 '$OPENMAINT_URL'"
su - ga -c "DISPLAY=:1 xdotool key Return"

if ! wait_for_rendered_browser_view /tmp/wob_start_screenshot.png 60; then
    echo "WARNING: Browser view did not stabilize"
fi

echo "=== multi_building_work_order_batch setup complete ==="
