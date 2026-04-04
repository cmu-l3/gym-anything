#!/bin/bash
set -e
echo "=== Setting up preventive_maintenance_schedule_setup ==="

source /workspace/scripts/task_utils.sh

if ! wait_for_openmaint 240; then
    echo "ERROR: OpenMaint is not reachable"
    exit 1
fi

# Discover PM class and record baselines
python3 << 'PYEOF'
import sys, json, os
sys.path.insert(0, "/workspace/scripts")
from cmdbuild_api import *

token = get_token()
if not token:
    print("ERROR: Could not authenticate", file=sys.stderr)
    sys.exit(1)

print("Authenticated to CMDBuild API")

# Find preventive maintenance class (may be a process or card class)
pm_type, pm_cls = find_pm_class(token)
print(f"PM class: {pm_cls} (type={pm_type})")

# Get PM class attributes
pm_attrs = {}
if pm_cls:
    attrs = get_record_attributes(pm_type, pm_cls, token)
    pm_attrs = {a.get("_id", ""): a for a in attrs}
    print(f"PM attributes: {list(pm_attrs.keys())[:30]}")

# Get buildings
buildings = get_buildings(token)
building_info = []
for b in buildings[:5]:
    building_info.append({
        "id": b.get("_id"),
        "code": b.get("Code", ""),
        "description": b.get("Description", ""),
    })
print(f"Buildings: {json.dumps(building_info, indent=2)}")

# Record baseline PM count
baseline_pm_count = count_records(pm_type, pm_cls, token) if pm_cls else 0
existing_pms = get_records(pm_type, pm_cls, token, limit=500) if pm_cls else []
existing_pm_ids = [p.get("_id") for p in existing_pms]
print(f"Baseline PM count: {baseline_pm_count}")

# Find field names for key attributes
building_field = None
frequency_field = None
priority_field = None
notes_field = None
checklist_field = None
status_field = None

for aname, ainfo in pm_attrs.items():
    alow = aname.lower()
    adesc = (ainfo.get("description", "") or "").lower()
    if "building" in alow or "location" in alow or "site" in alow:
        if not building_field:
            building_field = aname
    if "frequency" in alow or "recurrence" in alow or "interval" in alow or "period" in alow:
        if not frequency_field:
            frequency_field = aname
    if "priority" in alow:
        if not priority_field:
            priority_field = aname
    if "notes" in alow or "checklist" in alow or "task" in alow and "list" in alow:
        if not notes_field:
            notes_field = aname
    if "status" in alow and "flow" not in alow:
        if not status_field:
            status_field = aname

# Description and Notes are standard CMDBuild fields
if not notes_field:
    notes_field = "Notes"

print(f"Fields: building={building_field}, frequency={frequency_field}, "
      f"priority={priority_field}, notes={notes_field}")

baseline = {
    "pm_type": pm_type,
    "pm_class": pm_cls,
    "pm_attrs": list(pm_attrs.keys()),
    "building_field": building_field,
    "frequency_field": frequency_field,
    "priority_field": priority_field,
    "notes_field": notes_field,
    "status_field": status_field,
    "baseline_pm_count": baseline_pm_count,
    "existing_pm_ids": existing_pm_ids,
    "buildings": building_info,
}
save_baseline("/tmp/pm_baseline.json", baseline)
print("Baseline saved to /tmp/pm_baseline.json")
PYEOF

# Create PM requirements document on desktop
cat > /home/ga/Desktop/pm_requirements.txt << 'PMREQ'
=== QUARTERLY HVAC PREVENTIVE MAINTENANCE REQUIREMENTS ===

PROGRAM OVERVIEW:
Establish quarterly preventive maintenance for HVAC systems across all
company buildings. Each building requires its own PM activity card in
OpenMaint to enable independent scheduling and tracking.

NAMING CONVENTION:
  Code: PM-HVAC-Q-{BuildingCode}
  Example: PM-HVAC-Q-HQ for headquarters building

FREQUENCY: Every 90 days (quarterly)

PRIORITY: Medium / Normal

REQUIRED MAINTENANCE TASKS (include all in description/notes):
  1. Filter replacement - Replace all HVAC air filters (MERV-13 rated)
  2. Coil cleaning - Clean evaporator and condenser coils
  3. Refrigerant level check - Verify refrigerant charge levels
  4. Thermostat calibration - Calibrate all zone thermostats within ±1°F
  5. Condensate drain inspection - Clear and inspect all condensate drain lines

BUILDING ASSIGNMENT:
Each PM activity must be associated with the correct building record.
Create one PM activity per building — three total for the three office
buildings currently in the system.

IMPORTANT:
- Do NOT modify or delete existing maintenance records
- Each activity must be a NEW record
- All five maintenance tasks must be listed in the description or notes
PMREQ

chown ga:ga /home/ga/Desktop/pm_requirements.txt

date +%s > /tmp/pm_start_ts

# Restart browser
pkill -f firefox || true
sleep 1
su - ga -c "DISPLAY=:1 firefox '$OPENMAINT_URL' > /tmp/firefox_task_pm.log 2>&1 &"

if ! wait_for_window "firefox|mozilla|openmaint|cmdbuild" 40; then
    echo "WARNING: Firefox window not detected"
fi
focus_firefox || true
su - ga -c "DISPLAY=:1 xdotool key ctrl+l"
sleep 0.3
su - ga -c "DISPLAY=:1 xdotool type --delay 20 '$OPENMAINT_URL'"
su - ga -c "DISPLAY=:1 xdotool key Return"

if ! wait_for_rendered_browser_view /tmp/pm_start_screenshot.png 60; then
    echo "WARNING: Browser view did not stabilize"
fi

echo "=== preventive_maintenance_schedule_setup setup complete ==="
