#!/bin/bash
set -e
echo "=== Setting up holiday_shutdown_work_order_rescheduling ==="

source /workspace/scripts/task_utils.sh

# Wait for OpenMaint to be ready
if ! wait_for_openmaint 240; then
    echo "ERROR: OpenMaint is not reachable"
    exit 1
fi

# Create the Protocol Memo on Desktop
cat > /home/ga/Desktop/shutdown_protocol.txt << 'EOF'
MEMORANDUM
TO: Facilities Maintenance Team
FROM: Director of Operations
DATE: March 15, 2026
SUBJECT: SPRING BREAK SHUTDOWN PROTOCOL (April 6-10, 2026)

The campus will be closed for Spring Break from Monday, April 6, 2026 through Friday, April 10, 2026.
Building access will be restricted. Please adjust the maintenance schedule as follows:

1. AFFECTED DATES: 
   April 6, 2026 to April 10, 2026 (inclusive).

2. STANDARD MAINTENANCE:
   Any non-critical work orders (Priority: High, Medium/Normal, Low) scheduled during this week must be RESCHEDULED to the Resumption Date.
   
   RESUMPTION DATE: Monday, April 13, 2026.

3. CRITICAL MAINTENANCE:
   Work orders with "Critical" priority MUST proceed on their originally scheduled date.
   ACTION REQUIRED: Do not change the date. You must append the following text to the Description or Notes field to authorize security entry:
   
   "[SHUTDOWN ACCESS APPROVED]"

4. EXCEPTIONS:
   - Do not modify tickets that are already Closed or Completed.
   - Do not modify tickets scheduled outside the affected dates.

Thank you,
Management
EOF
chown ga:ga /home/ga/Desktop/shutdown_protocol.txt

# Seed Data via Python Script
python3 << 'PYEOF'
import sys, json, os
sys.path.insert(0, "/workspace/scripts")
from cmdbuild_api import *

token = get_token()
if not token:
    print("ERROR: Could not authenticate to CMDBuild API", file=sys.stderr)
    sys.exit(1)

print("Authenticated to CMDBuild API")

# Find Maintenance/WorkOrder Class
wo_type, wo_cls = find_maintenance_class(token)
if not wo_cls:
    print("ERROR: Could not find WorkOrder class", file=sys.stderr)
    sys.exit(1)
print(f"Using class: {wo_cls} (type={wo_type})")

# Get attributes to map field names
attrs = get_record_attributes(wo_type, wo_cls, token)
attr_map = {a.get("_id", ""): a for a in attrs}

# Detect field names
date_field = None
prio_field = None
desc_field = "Description"
status_field = None # usually _card_status or FlowStatus

for name in attr_map:
    n_low = name.lower()
    if "date" in n_low and ("scheduled" in n_low or "planned" in n_low or "start" in n_low):
        if not date_field: date_field = name
    if "priority" in n_low:
        if not prio_field: prio_field = name
    if "status" in n_low and "flow" not in n_low:
        if not status_field: status_field = name

# Fallback defaults if detection fails (common OpenMaint defaults)
if not date_field: date_field = "ScheduledDate" # or similar
if not prio_field: prio_field = "Priority"

print(f"Fields mapped: Date={date_field}, Priority={prio_field}")

# Define Seed Data
# Status values: depends on the workflow. Usually "Open", "Scheduled", "Completed".
# We will use codes to create specific scenarios.
seeds = [
    # Criticals in range (Action: Keep Date, Add Note)
    {"Code": "WO-SHUT-001", "Desc": "Annual Fire Alarm Testing - Building A", "Prio": "Critical", "Date": "2026-04-07", "Status": "Scheduled"},
    {"Code": "WO-SHUT-003", "Desc": "Server Room AC Inspection - Data Center", "Prio": "Critical", "Date": "2026-04-08", "Status": "Scheduled"},
    
    # Non-Criticals in range (Action: Reschedule to 2026-04-13)
    {"Code": "WO-SHUT-002", "Desc": "Paint 2nd Floor Hallway", "Prio": "Normal", "Date": "2026-04-07", "Status": "Scheduled"},
    {"Code": "WO-SHUT-004", "Desc": "Replace Lobby Carpet", "Prio": "Low", "Date": "2026-04-09", "Status": "Scheduled"},
    {"Code": "WO-SHUT-005", "Desc": "Breakroom Sink Repair", "Prio": "Normal", "Date": "2026-04-10", "Status": "Scheduled"},
    
    # Traps (Action: Do Nothing)
    {"Code": "WO-SHUT-006", "Desc": "Emergency Exit Sign Fix - COMPLETED", "Prio": "High", "Date": "2026-04-08", "Status": "Completed"}, # Completed status
    {"Code": "WO-SHUT-007", "Desc": "Monthly Generator Test - EARLY", "Prio": "High", "Date": "2026-04-01", "Status": "Scheduled"}, # Before range
    {"Code": "WO-SHUT-008", "Desc": "Window Washing - LATE", "Prio": "Low", "Date": "2026-04-15", "Status": "Scheduled"}, # After range
]

created_ids = {}

for seed in seeds:
    data = {
        "Code": seed["Code"],
        "Description": seed["Desc"]
    }
    
    # Set Date
    if date_field:
        data[date_field] = seed["Date"] # Format YYYY-MM-DD usually works
        
    # Set Priority - usually a lookup, might need to just send the code/description string and hope API handles it or find ID
    # For robustness, we try to just send the string. If that fails, the API wrapper might need enhancement, 
    # but typically cmdbuild accepts values if they match lookup codes.
    if prio_field:
        data[prio_field] = seed["Prio"].lower() # Try lowercase, common in lookups
        
    # Create the record
    # Note: Setting 'Status' often requires workflow transition, but we'll try setting it on create/update if it's a simple card.
    # If it's a process, we create it, then might need to advance it. 
    # For this task, we assume we can set fields.
    
    # Create
    rid = create_record(wo_type, wo_cls, data, token)
    if rid:
        print(f"Created {seed['Code']} with ID {rid}")
        created_ids[seed["Code"]] = rid
        
        # If status field exists, try to update it explicitly (for "Completed")
        if seed["Status"] == "Completed" and status_field:
            # Try to set status to closed/completed
            # This is tricky without knowing exact lookup IDs, but we try standard codes
            update_record(wo_type, wo_cls, rid, {status_field: "completed"}, token)
    else:
        print(f"Failed to create {seed['Code']}")

# Save baseline for export script
baseline = {
    "wo_type": wo_type,
    "wo_cls": wo_cls,
    "date_field": date_field,
    "prio_field": prio_field,
    "created_ids": created_ids,
    "seed_data": seeds
}
save_baseline("/tmp/shutdown_task_baseline.json", baseline)

PYEOF

# Prepare Firefox
pkill -f firefox || true
sleep 1

# Launch Firefox
su - ga -c "DISPLAY=:1 firefox '$OPENMAINT_URL' > /tmp/firefox_task.log 2>&1 &"

# Wait for window
if ! wait_for_window "firefox|mozilla|openmaint|cmdbuild" 40; then
    echo "WARNING: Firefox window not detected"
fi

focus_firefox || true

# Attempt to navigate to login
su - ga -c "DISPLAY=:1 xdotool key ctrl+l"
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool type '$OPENMAINT_URL'"
su - ga -c "DISPLAY=:1 xdotool key Return"

echo "=== Setup complete ==="