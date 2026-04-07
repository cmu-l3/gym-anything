#!/bin/bash
echo "=== Exporting Triage Sick Day Schedule Results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Use Python to query the final state of the database
python3 << 'PYTHON_EOF'
import xmlrpc.client
import json
import sys
from datetime import datetime

url = 'http://localhost:8069'
db = 'odoo_scheduling'
username = 'admin'
password = 'admin'

output = {
    "standup": {"exists": False, "attendees": [], "start": ""},
    "review": {"exists": False, "start": "", "duration": 0},
    "one_on_one": {"exists": False}
}

try:
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, username, password, {})
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')

    # Check 1: Team Standup
    standups = models.execute_kw(db, uid, password, 'calendar.event', 'search_read',
        [[['name', '=', 'Team Standup']]],
        {'fields': ['partner_ids', 'start']})
    
    if standups:
        # Get attendee names
        event = standups[0]
        pids = event['partner_ids']
        if pids:
            partners = models.execute_kw(db, uid, password, 'res.partner', 'read',
                [pids], {'fields': ['name']})
            attendee_names = [p['name'] for p in partners]
        else:
            attendee_names = []
            
        output["standup"] = {
            "exists": True,
            "attendees": attendee_names,
            "start": event['start']
        }

    # Check 2: Q2 Financial Review
    reviews = models.execute_kw(db, uid, password, 'calendar.event', 'search_read',
        [[['name', '=', 'Q2 Financial Review']]],
        {'fields': ['start', 'duration', 'partner_ids']})
    
    if reviews:
        event = reviews[0]
        output["review"] = {
            "exists": True,
            "start": event['start'],
            "duration": event['duration']
        }

    # Check 3: One-on-One with Mentor
    # Search for active=True events first
    mentors = models.execute_kw(db, uid, password, 'calendar.event', 'search_count',
        [[['name', '=', 'One-on-One with Mentor']]])
    
    # Also check if it exists but is inactive (archived), though usually delete = unlink
    output["one_on_one"]["exists"] = (mentors > 0)
    
    # Get Target Monday Date from setup file to verify relative shifts
    try:
        with open("/tmp/target_date.txt", "r") as f:
            target_date = f.read().strip()
        output["target_monday"] = target_date
    except:
        output["target_monday"] = ""

except Exception as e:
    output["error"] = str(e)

with open("/tmp/task_result.json", "w") as f:
    json.dump(output, f, indent=2)

print("Exported JSON result.")
PYTHON_EOF

# Ensure permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export Complete ==="
cat /tmp/task_result.json