#!/bin/bash
set -e
echo "=== Setting up weekend_incident_log_entry ==="

source /workspace/scripts/task_utils.sh

# Ensure OpenMaint is reachable
if ! wait_for_openmaint 240; then
    echo "ERROR: OpenMaint is not reachable"
    exit 1
fi

# Create the security log file on the desktop
mkdir -p /home/ga/Desktop
cat > /home/ga/Desktop/weekend_security_log.txt << 'EOF'
=== WEEKEND SECURITY INCIDENT LOG ===
Recorded by: Officer J. Ramirez
Shift: Saturday 18:00 - Monday 06:00

INCIDENT 1 - Sat 22:15
Location: Building A, near server room (basement level)
Water pooling on floor near server room entry door. Appears to be
coming from overhead pipe. Placed wet floor sign. Recommend urgent
attention — potential electrical hazard if water reaches server racks.
Suggested Code: SEC-MON-001

INCIDENT 2 - Sat 23:45
Location: Building A, Room 102
Lights buzzing and flickering on and off. Noticed during patrol.
May be a ballast issue. Room was unoccupied.
[NOTE: This appears similar to a maintenance request already
submitted by the office manager last Friday]

INCIDENT 3 - Sun 02:30
Location: Building B, ground floor east wing
Window latch broken on exterior window near east stairwell.
Window can be pushed open from outside. Security concern.
Suggested Code: SEC-MON-002

INCIDENT 4 - Sun 08:00
Location: Building B, 2nd floor men's restroom
Faucet in second sink from left dripping continuously.
Water running but slowly. Bucket placed underneath.
[NOTE: Office staff mentioned this was reported to maintenance
last week already]

INCIDENT 5 - Sun 14:20
Location: Building C, parking garage level P2
Emergency exit light above stairwell door is dark / not
illuminated. Checked breaker panel — breakers are fine.
Likely bulb or unit failure.
Suggested Code: SEC-MON-003

INCIDENT 6 - Sun 19:45
Location: Building A, Room 102
Ceiling tile sagging noticeably near window side of room.
Possibly water damage from recent rain. DIFFERENT issue from
the lighting problem reported earlier — this is structural.
Suggested Code: SEC-MON-004
===
EOF
chown ga:ga /home/ga/Desktop/weekend_security_log.txt

# Setup DB state via Python
python3 << 'PYEOF'
import sys, json, os, random
sys.path.insert(0, "/workspace/scripts")
from cmdbuild_api import *

token = get_token()
if not token:
    print("ERROR: Could not authenticate to CMDBuild API", file=sys.stderr)
    sys.exit(1)

# 1. Identify Ticket Class
ticket_type, ticket_cls = find_maintenance_class(token)
if not ticket_cls:
    print("ERROR: Could not find maintenance ticket class", file=sys.stderr)
    sys.exit(1)
print(f"Using ticket class: {ticket_cls} (type={ticket_type})")

# 2. Identify Buildings
buildings = get_buildings(token)
# Ensure we have enough buildings or map A/B/C to what exists
b_map = {} # 'A' -> id, 'B' -> id, etc.
if len(buildings) >= 3:
    b_map['A'] = buildings[0]["_id"]
    b_map['B'] = buildings[1]["_id"]
    b_map['C'] = buildings[2]["_id"]
    print(f"Mapped Buildings: A={buildings[0].get('Description')}, B={buildings[1].get('Description')}, C={buildings[2].get('Description')}")
else:
    # Fallback if fewer buildings exist
    print("WARNING: Not enough buildings found, mapping all to first building")
    if buildings:
        b_map['A'] = buildings[0]["_id"]
        b_map['B'] = buildings[0]["_id"]
        b_map['C'] = buildings[0]["_id"]

# 3. Identify Fields
attrs = get_record_attributes(ticket_type, ticket_cls, token) if ticket_cls else []
attr_map = {a.get("_id", ""): a for a in attrs}
priority_field = next((k for k in attr_map if "priority" in k.lower()), "Priority")
building_field = next((k for k in attr_map if "building" in k.lower() or "location" in k.lower()), "Building")

# 4. Create Pre-existing Tickets (Duplicates)
existing_tickets = [
    {
        "Code": "WO-EXIST-101",
        "Description": "Flickering fluorescent lights in Room 102 - ballast noise",
        "building": "A",
        "priority": "medium"
    },
    {
        "Code": "WO-EXIST-102",
        "Description": "Leaking faucet in 2nd floor men's restroom - slow drip",
        "building": "B",
        "priority": "low"
    }
]

created_ids = []
for t in existing_tickets:
    data = {
        "Code": t["Code"],
        "Description": t["Description"]
    }
    if building_field and t["building"] in b_map:
        data[building_field] = b_map[t["building"]]
    if priority_field:
        data[priority_field] = t["priority"]
    
    # Create
    rid = create_record(ticket_type, ticket_cls, data, token)
    if rid:
        created_ids.append(rid)
        print(f"Created pre-existing ticket {t['Code']}")

# 5. Save Baseline
baseline = {
    "ticket_type": ticket_type,
    "ticket_cls": ticket_cls,
    "building_map": b_map,
    "pre_existing_ids": created_ids,
    "priority_field": priority_field,
    "building_field": building_field
}
save_baseline("/tmp/wsl_baseline.json", baseline)
PYEOF

# Record start timestamp
date +%s > /tmp/task_start_time.txt

# Launch Firefox to Login Page
pkill -f firefox || true
sleep 1
su - ga -c "DISPLAY=:1 firefox '$OPENMAINT_URL' > /tmp/firefox_log.txt 2>&1 &"
sleep 5
# Maximize
wid=$(DISPLAY=:1 wmctrl -l | grep -i "firefox" | awk '{print $1}' | head -1)
if [ -n "$wid" ]; then
    DISPLAY=:1 wmctrl -ia "$wid"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz
fi

echo "=== Setup complete ==="