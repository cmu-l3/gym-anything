#!/bin/bash
set -e
echo "=== Setting up Event Support Ticket Consolidation task ==="

source /workspace/scripts/task_utils.sh

# Wait for OpenMaint to be ready
if ! wait_for_openmaint 240; then
    echo "ERROR: OpenMaint is not reachable"
    exit 1
fi

# Record task start time
date +%s > /tmp/task_start_time.txt

# Seed data using Python script
python3 << 'PYEOF'
import sys, json, os, time
sys.path.insert(0, "/workspace/scripts")
from cmdbuild_api import *

token = get_token()
if not token:
    print("ERROR: Failed to authenticate", file=sys.stderr)
    sys.exit(1)

# Detect Maintenance Class
maint_type, maint_class = find_maintenance_class(token)
if not maint_class:
    print("ERROR: Maintenance class not found", file=sys.stderr)
    sys.exit(1)

print(f"Using class: {maint_class} ({maint_type})")

# Get Priority IDs
priorities = get_lookup_values("Priority", token)
p_map = {p.get("description", "").lower(): p.get("_id") for p in priorities}
if not p_map:
    # Fallback if description is missing or different structure
    p_map = {p.get("code", "").lower(): p.get("_id") for p in priorities}

high_id = p_map.get("high") or p_map.get("urgent") or p_map.get("critical")
med_id = p_map.get("medium") or p_map.get("normal")
low_id = p_map.get("low")

# If priorities not found, just use first available (unlikely in demo db)
if not high_id and priorities: high_id = priorities[-1]["_id"]
if not med_id and priorities: med_id = priorities[len(priorities)//2]["_id"]
if not low_id and priorities: low_id = priorities[0]["_id"]

print(f"Priorities: High={high_id}, Med={med_id}, Low={low_id}")

# Create Tickets
tickets = []

# 1. Gala - Ballroom Chair Setup (Active, Medium)
t1_data = {
    "Description": "Gala - Ballroom Chair Setup. Arrange 200 chairs in theater style.",
    "Priority": med_id,
    "Notes": "Setup required by 14:00."
}
t1 = create_record(maint_type, maint_class, t1_data, token)
tickets.append({"id": t1, "role": "child_1", "desc": t1_data["Description"]})

# 2. Gala - HVAC Temp Adjust (Active, High)
t2_data = {
    "Description": "Gala - HVAC Temp Adjust. Override schedule for Main Hall.",
    "Priority": high_id,
    "Notes": "Critical for guest comfort."
}
t2 = create_record(maint_type, maint_class, t2_data, token)
tickets.append({"id": t2, "role": "child_2", "desc": t2_data["Description"]})

# 3. Gala - Post-Event Cleaning (Active, Low)
t3_data = {
    "Description": "Gala - Post-Event Cleaning. Standard cleanup after event.",
    "Priority": low_id,
    "Notes": "Start after 22:00."
}
t3 = create_record(maint_type, maint_class, t3_data, token)
tickets.append({"id": t3, "role": "child_3", "desc": t3_data["Description"]})

# 4. Galactic Server Maintenance (Active, Trap - Keyword Match)
t4_data = {
    "Description": "Galactic Server Maintenance. Upgrade firmware on node 4.",
    "Priority": med_id,
    "Notes": "IT Dept only."
}
t4 = create_record(maint_type, maint_class, t4_data, token)
tickets.append({"id": t4, "role": "trap_keyword", "desc": t4_data["Description"]})

# 5. Gala - Catering Delivery (Closed, Trap - Status)
# We simulate "Closed" by putting explicit text in description if we can't easily change workflow status via API
t5_data = {
    "Description": "[COMPLETED] Gala - Catering Delivery. Delivered to kitchen.",
    "Priority": low_id,
    "Notes": "Task completed yesterday."
}
# Try to set status if possible (for card classes)
status_lookup = get_lookup_values("UserStatus", token) or get_lookup_values("Status", token)
closed_id = None
for s in status_lookup:
    if "close" in s.get("description", "").lower() or "complete" in s.get("description", "").lower():
        closed_id = s.get("_id")
        break
if closed_id:
    t5_data["Status"] = closed_id

t5 = create_record(maint_type, maint_class, t5_data, token)
tickets.append({"id": t5, "role": "trap_closed", "desc": t5_data["Description"]})

print(f"Seeded {len(tickets)} tickets.")

# Save Baseline
baseline = {
    "maint_type": maint_type,
    "maint_class": maint_class,
    "seeded_tickets": tickets,
    "high_priority_id": high_id
}

with open('/tmp/gala_baseline.json', 'w') as f:
    json.dump(baseline, f)
PYEOF

# Start Firefox with OpenMaint
pkill -f firefox || true
sleep 1
su - ga -c "DISPLAY=:1 firefox '$OPENMAINT_URL' > /tmp/firefox_gala.log 2>&1 &"

if ! wait_for_window "firefox|mozilla|openmaint" 45; then
    echo "WARNING: Firefox window not detected"
fi

focus_firefox || true

# Initial Screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="