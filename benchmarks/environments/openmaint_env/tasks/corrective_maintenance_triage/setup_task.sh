#!/bin/bash
set -e
echo "=== Setting up corrective_maintenance_triage ==="

source /workspace/scripts/task_utils.sh

if ! wait_for_openmaint 240; then
    echo "ERROR: OpenMaint is not reachable"
    exit 1
fi

# Seed test data and record baselines via Python (CMDBuild REST API)
python3 << 'PYEOF'
import sys, json, os, time
sys.path.insert(0, "/workspace/scripts")
from cmdbuild_api import *

token = get_token()
if not token:
    print("ERROR: Could not authenticate to CMDBuild API", file=sys.stderr)
    sys.exit(1)

print("Authenticated to CMDBuild API")

# Discover corrective maintenance class/process
ticket_type, ticket_cls = find_maintenance_class(token)
if not ticket_cls:
    print("ERROR: Could not find corrective maintenance class or process", file=sys.stderr)
    sys.exit(1)

print(f"Ticket class: {ticket_cls} (type={ticket_type})")

# Get existing buildings
buildings = get_buildings(token)
if len(buildings) < 3:
    print(f"WARNING: Only {len(buildings)} buildings found, expected >= 3")

building_ids = []
building_names = []
for b in buildings[:3]:
    building_ids.append(b.get("_id"))
    building_names.append(b.get("Description", b.get("Code", "Unknown")))

print(f"Buildings: {list(zip(building_ids, building_names))}")

# Discover ticket class attributes to know valid field names
attrs = get_record_attributes(ticket_type, ticket_cls, token) if ticket_cls else []
attr_names = {a.get("_id", ""): a for a in attrs}
print(f"Ticket attributes: {list(attr_names.keys())[:20]}")

# Determine field names for priority, category, description, etc.
priority_field = None
category_field = None
status_field = None
assignee_field = None
building_field = None
desc_field = "Description"

for aname, ainfo in attr_names.items():
    aname_lower = aname.lower()
    adesc_lower = (ainfo.get("description", "") or "").lower()
    if "priority" in aname_lower or "priority" in adesc_lower:
        priority_field = aname
    if "category" in aname_lower or "type" in aname_lower and "class" not in aname_lower:
        if not category_field:
            category_field = aname
    if "status" in aname_lower and "flow" not in aname_lower:
        if not status_field:
            status_field = aname
    if "assign" in aname_lower or "technic" in aname_lower or "operator" in aname_lower:
        if not assignee_field:
            assignee_field = aname
    if "building" in aname_lower or "location" in aname_lower:
        if not building_field:
            building_field = aname

print(f"Fields: priority={priority_field}, category={category_field}, "
      f"status={status_field}, assignee={assignee_field}, building={building_field}")

# Record baseline: count existing tickets
baseline_count = count_records(ticket_type, ticket_cls, token) if ticket_cls else 0
print(f"Baseline ticket count: {baseline_count}")

# Get existing ticket IDs to track new vs old
existing_tickets = get_records(ticket_type, ticket_cls, token, limit=500) if ticket_cls else []
existing_ids = [t.get("_id") for t in existing_tickets]

# Define 6 new tickets to seed
tickets_to_create = [
    {
        "tag": "GAS_LEAK",
        "Code": "CMT-2026-001",
        "Description": "Gas leak detected in basement utility room - strong odor reported by security at 02:15 AM",
        "expected_priority": "critical",
        "seeded_priority": "low",
        "seeded_category": "plumbing",
        "building_idx": 0,
        "is_duplicate": False,
        "is_contamination": False,
    },
    {
        "tag": "WINDOW_LATCH",
        "Code": "CMT-2026-002",
        "Description": "Broken window latch in Room 204 - window cannot be secured, security risk",
        "expected_priority": "medium",
        "seeded_priority": "low",
        "seeded_category": "electrical",
        "building_idx": 1,
        "is_duplicate": False,
        "is_contamination": False,
    },
    {
        "tag": "EMERGENCY_LIGHT",
        "Code": "CMT-2026-003",
        "Description": "Emergency lighting failure in main stairwell - fire code violation, all 3 exit signs dark",
        "expected_priority": "critical",
        "seeded_priority": "medium",
        "seeded_category": "electrical",
        "building_idx": 2,
        "is_duplicate": False,
        "is_contamination": False,
    },
    {
        "tag": "HVAC_OVERHEAT",
        "Code": "CMT-2026-004",
        "Description": "HVAC thermostat reading 45C in server room - cooling system unresponsive, equipment at risk",
        "expected_priority": "critical",
        "seeded_priority": "medium",
        "seeded_category": "plumbing",
        "building_idx": 0,
        "is_duplicate": False,
        "is_contamination": False,
    },
    {
        "tag": "PAINT_PEEL_DUP",
        "Code": "CMT-2026-005",
        "Description": "Paint peeling in main corridor near elevator bank - cosmetic, low urgency",
        "expected_priority": "low",
        "seeded_priority": "low",
        "seeded_category": "structural",
        "building_idx": 1,
        "is_duplicate": True,
        "is_contamination": False,
    },
    {
        "tag": "PAINT_PEEL_LEGIT",
        "Code": "CMT-2026-006",
        "Description": "Paint peeling in lobby entrance area near main door - cosmetic, low urgency",
        "expected_priority": "low",
        "seeded_priority": "low",
        "seeded_category": "structural",
        "building_idx": 2,
        "is_duplicate": False,
        "is_contamination": True,
    },
]

# Also create the "original" ticket that CMT-2026-005 duplicates
original_ticket_data = {
    "Code": "CMT-2026-000",
    "Description": "Paint peeling in main corridor near elevator bank - reported by tenant",
}
if priority_field:
    original_ticket_data[priority_field] = "low"
if building_field and building_ids:
    original_ticket_data[building_field] = building_ids[1]

original_id = create_record(ticket_type, ticket_cls, original_ticket_data, token)
print(f"Created original ticket (for duplicate reference): {original_id}")

# Create the 6 seeded tickets
seeded_ids = {}
for t in tickets_to_create:
    card_data = {
        "Code": t["Code"],
        "Description": t["Description"],
    }
    if priority_field:
        card_data[priority_field] = t["seeded_priority"]
    if category_field:
        card_data[category_field] = t["seeded_category"]
    if building_field and building_ids and t["building_idx"] < len(building_ids):
        card_data[building_field] = building_ids[t["building_idx"]]

    card_id = create_record(ticket_type, ticket_cls, card_data, token)
    seeded_ids[t["tag"]] = card_id
    print(f"Created ticket {t['Code']} ({t['tag']}): id={card_id}")

# Save baseline data
baseline = {
    "ticket_type": ticket_type,
    "ticket_class": ticket_cls,
    "priority_field": priority_field,
    "category_field": category_field,
    "status_field": status_field,
    "assignee_field": assignee_field,
    "building_field": building_field,
    "baseline_count": baseline_count,
    "existing_ids": existing_ids,
    "original_ticket_id": original_id,
    "seeded_ids": seeded_ids,
    "building_ids": building_ids,
    "building_names": building_names,
    "tickets_spec": {t["tag"]: {
        "code": t["Code"],
        "expected_priority": t["expected_priority"],
        "is_duplicate": t["is_duplicate"],
        "is_contamination": t["is_contamination"],
        "building_idx": t["building_idx"],
    } for t in tickets_to_create},
}
save_baseline("/tmp/cmt_baseline.json", baseline)
print("Baseline saved to /tmp/cmt_baseline.json")
print(json.dumps(baseline, indent=2))
PYEOF

# Create triage instruction file on desktop
cat > /home/ga/Desktop/triage_instructions.txt << 'TRIAGE'
=== CORRECTIVE MAINTENANCE TRIAGE REFERENCE ===

PRIORITY CLASSIFICATION:
- CRITICAL: Gas leaks, fire safety violations (emergency lighting, sprinklers),
  equipment overheating that risks damage, structural collapse risks.
  Action: Assign immediately, escalate to supervisor.

- MEDIUM/HIGH: Security risks (broken locks, window latches), water leaks
  (non-emergency), HVAC issues affecting comfort but not equipment.
  Action: Assign within 4 hours.

- LOW: Cosmetic issues (paint peeling, carpet stains, scuff marks),
  minor furniture damage, non-urgent replacements.
  Action: Add to weekly maintenance queue.

CATEGORY CORRECTIONS:
- Gas leak → Mechanical/HVAC (not Plumbing)
- Window latch → Structural/Building Envelope (not Electrical)
- Emergency lighting → Electrical (correct)
- HVAC thermostat → Mechanical/HVAC (not Plumbing)
- Paint peeling → Structural/Cosmetic (correct)

DUPLICATE DETECTION:
- Two tickets for "paint peeling near elevator" exist for the same building.
  Close the newer one (CMT-2026-005) as duplicate, keep the original.
- NOTE: A similar "paint peeling in lobby" ticket exists for a DIFFERENT building.
  This is NOT a duplicate — it is a separate legitimate request.

ASSIGNMENT:
- All tickets must be assigned to a technician/staff member before triage is complete.
TRIAGE

chown ga:ga /home/ga/Desktop/triage_instructions.txt

# Record task start timestamp
date +%s > /tmp/cmt_start_ts

# Restart browser with clean session
pkill -f firefox || true
sleep 1

su - ga -c "DISPLAY=:1 firefox '$OPENMAINT_URL' > /tmp/firefox_task_cmt.log 2>&1 &"

if ! wait_for_window "firefox|mozilla|openmaint|cmdbuild" 40; then
    echo "WARNING: Firefox window not detected"
fi

focus_firefox || true
su - ga -c "DISPLAY=:1 xdotool key ctrl+l"
sleep 0.3
su - ga -c "DISPLAY=:1 xdotool type --delay 20 '$OPENMAINT_URL'"
su - ga -c "DISPLAY=:1 xdotool key Return"

if ! wait_for_rendered_browser_view /tmp/cmt_start_screenshot.png 60; then
    echo "WARNING: Browser view did not stabilize"
fi

echo "=== corrective_maintenance_triage setup complete ==="
