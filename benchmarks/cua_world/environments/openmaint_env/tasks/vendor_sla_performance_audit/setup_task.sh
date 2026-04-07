#!/bin/bash
set -e
echo "=== Setting up Vendor SLA Performance Audit ==="

source /workspace/scripts/task_utils.sh

# Wait for OpenMaint to be ready
if ! wait_for_openmaint 240; then
    echo "ERROR: OpenMaint is not reachable"
    exit 1
fi

# Create the Policy Document on Desktop
cat > /home/ga/Desktop/SLA_Policy.txt << 'EOF'
=== VENDOR SLA AUDIT POLICY ===
Date: 2026-05-15

OBJECTIVE:
Verify compliance with the "Critical Response Guarantee".

RULE:
All "Critical" and "High" priority Work Orders must be RESOLVED within 24 HOURS of being REPORTED.

TAGGING INSTRUCTIONS:
Audit the seeded Work Orders and update their Description field by prepending one of the following tags:

1. [SLA: COMPLIANT]
   - Use if (Resolved Time - Reported Time) <= 24 hours.

2. [SLA: BREACHED]
   - Use if (Resolved Time - Reported Time) > 24 hours.

3. [SLA: EXEMPT]
   - Use if the ticket notes indicate "Waiting for Parts" or "On Hold". These stop the SLA clock.

4. NO TAG
   - If the ticket is not yet resolved (no Resolved timestamp), do not modify it.

TARGET WORK ORDERS TO AUDIT:
- WO-SLA-001
- WO-SLA-002
- WO-SLA-003
- WO-SLA-004
- WO-SLA-005
- WO-SLA-006
EOF
chown ga:ga /home/ga/Desktop/SLA_Policy.txt

# Seed Data via Python API
python3 << 'PYEOF'
import sys, json, os, time
sys.path.insert(0, "/workspace/scripts")
from cmdbuild_api import *

token = get_token()
if not token:
    print("ERROR: Authentication failed", file=sys.stderr)
    sys.exit(1)

# Find WO class
wo_type, wo_cls = find_maintenance_class(token)
print(f"Using WorkOrder Class: {wo_cls} ({wo_type})")

# Data to seed
# Time format in desc: YYYY-MM-DD HH:MM
seed_data = [
    {
        "Code": "WO-SLA-001",
        "Description": "Reported: 2026-05-10 08:00 | Resolved: 2026-05-10 14:00 | Issue: Main lobby AC not cooling. Technician arrived and refilled refrigerant.",
        "Priority": "High"
    },
    {
        "Code": "WO-SLA-002",
        "Description": "Reported: 2026-05-11 09:00 | Resolved: 2026-05-12 09:30 | Issue: Elevator 2 door stuck. Sensor replaced.",
        "Priority": "Critical"
    },
    {
        "Code": "WO-SLA-003",
        "Description": "Reported: 2026-05-12 10:00 | Resolved: 2026-05-13 09:00 | Issue: Power outage in West Wing server room. Breaker reset.",
        "Priority": "Critical"
    },
    {
        "Code": "WO-SLA-004",
        "Description": "Reported: 2026-05-13 08:00 | Resolved: 2026-05-14 16:00 | Issue: Water leak in 4th floor restroom. Pipe replaced.",
        "Priority": "High"
    },
    {
        "Code": "WO-SLA-005",
        "Description": "Reported: 2026-05-10 08:00 | Resolved: 2026-05-13 12:00 | Issue: Generator ATS failure. STATUS: Waiting for Parts (Control Board) - Vendor delay.",
        "Priority": "Critical"
    },
    {
        "Code": "WO-SLA-006",
        "Description": "Reported: 2026-05-15 12:00 | Issue: Fire alarm panel beeping. Investigation ongoing.",
        "Priority": "High"
    }
]

seeded_ids = {}

for item in seed_data:
    # Check if exists, delete if so (for idempotency)
    existing = get_cards(wo_cls, token, limit=1, filter_str=f"filter={{\"attribute\":{{\"simple\":{{\"attribute\":\"Code\",\"operator\":\"equal\",\"value\":\"{item['Code']}\"}}}}}}")
    if existing:
        delete_card(wo_cls, existing[0]['_id'], token)
        print(f"Deleted existing {item['Code']}")
    
    # Create new
    payload = {
        "Code": item["Code"],
        "Description": item["Description"]
    }
    
    # Try to set priority if we can guess the field name (it varies by setup)
    # This is "best effort" for priority, but Description contains the critical data
    
    rid = create_record(wo_type, wo_cls, payload, token)
    seeded_ids[item["Code"]] = rid
    print(f"Created {item['Code']} -> {rid}")

# Save baseline for verifier
baseline = {
    "wo_cls": wo_cls,
    "wo_type": wo_type,
    "seeded_ids": seeded_ids
}
save_baseline("/tmp/sla_baseline.json", baseline)
PYEOF

# Record Start Time
date +%s > /tmp/task_start_time.txt

# Launch Firefox
pkill -f firefox || true
sleep 1
su - ga -c "DISPLAY=:1 firefox '$OPENMAINT_URL' > /tmp/firefox.log 2>&1 &"

# Wait for window and maximize
wait_for_window "firefox|mozilla|openmaint" 60
focus_firefox || true

# Login if needed (though session might persist, explicit login logic is handled by agent usually, but we ensure page is loaded)
su - ga -c "DISPLAY=:1 xdotool key ctrl+l"
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool type '$OPENMAINT_URL'"
su - ga -c "DISPLAY=:1 xdotool key Return"

echo "=== Setup Complete ==="