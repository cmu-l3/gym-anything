#!/bin/bash
set -e
echo "=== Exporting Event Support Ticket Consolidation Results ==="

source /workspace/scripts/task_utils.sh

# Capture final screenshot
take_screenshot /tmp/task_final.png

# Run Python export script
python3 << 'PYEOF'
import sys, json, os
sys.path.insert(0, "/workspace/scripts")
from cmdbuild_api import *

# Load Baseline
try:
    with open('/tmp/gala_baseline.json') as f:
        baseline = json.load(f)
except FileNotFoundError:
    print("ERROR: Baseline file not found", file=sys.stderr)
    with open('/tmp/gala_result.json', 'w') as f:
        json.dump({"error": "baseline_missing"}, f)
    sys.exit(0)

token = get_token()
if not token:
    print("ERROR: Auth failed", file=sys.stderr)
    with open('/tmp/gala_result.json', 'w') as f:
        json.dump({"error": "auth_failed"}, f)
    sys.exit(0)

maint_type = baseline['maint_type']
maint_class = baseline['maint_class']
seeded_tickets = baseline['seeded_tickets']
seeded_ids = [t['id'] for t in seeded_tickets]

# 1. Find the Master Ticket (New ticket created by agent)
# Strategy: Look for tickets NOT in seeded_ids
all_records = get_records(maint_type, maint_class, token, limit=100)
master_ticket = None

for r in all_records:
    rid = r.get('_id')
    if rid in seeded_ids:
        continue
    
    desc = (r.get('Description', '') or "").lower()
    # Loose match for master ticket description
    if "master" in desc and "gala" in desc:
        master_ticket = r
        break

master_info = {}
if master_ticket:
    # Check priority
    prio_val = master_ticket.get('Priority')
    prio_id = prio_val if isinstance(prio_val, str) else prio_val.get('_id') if isinstance(prio_val, dict) else None
    
    master_info = {
        "found": True,
        "id": master_ticket.get('_id'),
        "code": master_ticket.get('Code'),
        "description": master_ticket.get('Description'),
        "priority_id": prio_id,
        "expected_high_id": baseline['high_priority_id']
    }
else:
    master_info = {"found": False}

# 2. Check Seeded Tickets
ticket_states = {}
for ticket in seeded_tickets:
    tid = ticket['id']
    role = ticket['role']
    
    curr = get_record(maint_type, maint_class, tid, token)
    if not curr:
        ticket_states[role] = {"exists": False}
        continue
        
    ticket_states[role] = {
        "exists": True,
        "description": curr.get('Description', ''),
        "original_desc": ticket['desc'],
        "id": tid
    }

result = {
    "master_ticket": master_info,
    "ticket_states": ticket_states
}

with open('/tmp/gala_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print("Export completed to /tmp/gala_result.json")
PYEOF

# Ensure permissions
chmod 666 /tmp/gala_result.json 2>/dev/null || true