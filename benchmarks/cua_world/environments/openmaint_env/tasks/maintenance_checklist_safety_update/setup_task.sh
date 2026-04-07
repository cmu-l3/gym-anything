#!/bin/bash
set -e
echo "=== Setting up maintenance_checklist_safety_update ==="

source /workspace/scripts/task_utils.sh

# Wait for OpenMaint to be ready
if ! wait_for_openmaint 240; then
    echo "ERROR: OpenMaint is not reachable"
    exit 1
fi

# Create the Safety Directive file on the desktop
cat > /home/ga/Desktop/safety_directive_2026.txt << 'EOF'
SAFETY COMMITTEE DIRECTIVE - IMMEDIATE ACTION REQUIRED
Date: March 15, 2026
Re: Maintenance Checklist Updates for Compliance

The following changes must be made to the OpenMaint Preventive Maintenance definitions immediately:

1. HIGH VOLTAGE PANELS (Code: PM-ELEC-01)
   - Risk of Arc Flash identified.
   - Action: Update description to include "REQUIREMENT: Wear Arc Flash PPE Category 4".
   - Action: Increase allotted time to 90 minutes to allow for suiting up.

2. CHILLER ANNUAL SERVICE (Code: PM-CHILLER-01)
   - LOTO violations observed.
   - Action: Add "WARNING: Ensure Lockout/Tagout procedures are followed" to the description.
   - Action: Increase allotted time to 240 minutes.

3. BOILERS (Code: PM-BOILER-01)
   - General "check pressure" instruction is insufficient.
   - Action: Change description to specify "Verify pressure is between 20-25 PSI".
   - Time allocation is sufficient (do not change).

NOTE: All other HVAC tasks, including Air Handling Unit filter changes (PM-AHU-02), have been reviewed and are compliant. Do not modify them.
EOF
chown ga:ga /home/ga/Desktop/safety_directive_2026.txt

# Seed the PM records via Python API
python3 << 'PYEOF'
import sys, json, os
sys.path.insert(0, "/workspace/scripts")
from cmdbuild_api import *

token = get_token()
if not token:
    print("ERROR: Could not authenticate to CMDBuild API", file=sys.stderr)
    sys.exit(1)

print("Authenticated to CMDBuild API")

# Find Preventive Maintenance Class
pm_type, pm_cls = find_pm_class(token)
if not pm_cls:
    print("ERROR: Could not find PM class", file=sys.stderr)
    sys.exit(1)

print(f"PM Class: {pm_cls} ({pm_type})")

# Identify fields
attrs = get_record_attributes(pm_type, pm_cls, token)
attr_map = {a.get("_id"): a for a in attrs}

duration_field = None
for name in attr_map:
    lower = name.lower()
    if "duration" in lower or "time" in lower or "estimated" in lower:
        duration_field = name
        break
# Fallback if no specific duration field found, we might use Notes or assume 'Duration'
if not duration_field:
    duration_field = "Duration" 

print(f"Duration field identified as: {duration_field}")

# Records to seed
seeds = [
    {
        "Code": "PM-CHILLER-01",
        "Description": "Annual Chiller Service - Clean tubes and inspect controls.",
        duration_field: 120
    },
    {
        "Code": "PM-BOILER-01",
        "Description": "Monthly Boiler Check - Check pressure and temp gauges.",
        duration_field: 45
    },
    {
        "Code": "PM-ELEC-01",
        "Description": "HV Panel Inspect - Thermal scan of breakers.",
        duration_field: 60
    },
    {
        "Code": "PM-AHU-02",
        "Description": "AHU Filter Change - Replace MERV-8 pre-filters.",
        duration_field: 60
    }
]

# Create or Update records
seeded_ids = {}
initial_states = {}

for seed in seeds:
    code = seed["Code"]
    
    # Check if exists
    existing = get_cards(pm_cls, token, limit=1, filter_str=f"filter={{\"attribute\":{{\"simple\":{{\"attribute\":\"Code\",\"operator\":\"equal\",\"value\":[\"{code}\"]}}}}}}")
    
    card_data = seed.copy()
    
    if existing:
        card_id = existing[0]["_id"]
        update_card(pm_cls, card_id, card_data, token)
        print(f"Updated existing record {code}")
    else:
        card_id = create_card(pm_cls, card_data, token)
        print(f"Created new record {code}")
    
    if card_id:
        seeded_ids[code] = card_id
        initial_states[code] = {
            "description": card_data["Description"],
            "duration": card_data.get(duration_field, 0)
        }

# Save baseline for export/verification
baseline = {
    "pm_cls": pm_cls,
    "pm_type": pm_type,
    "duration_field": duration_field,
    "seeded_ids": seeded_ids,
    "initial_states": initial_states
}

with open("/tmp/safety_update_baseline.json", "w") as f:
    json.dump(baseline, f)
    
PYEOF

# Start Firefox
pkill -f firefox || true
sleep 1
su - ga -c "DISPLAY=:1 firefox '$OPENMAINT_URL' > /tmp/firefox_task.log 2>&1 &"

if ! wait_for_window "firefox|mozilla|openmaint|cmdbuild" 60; then
    echo "WARNING: Firefox window not detected"
fi

focus_firefox || true
maximize_window "Firefox"

# Capture initial state
date +%s > /tmp/task_start_time.txt
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="