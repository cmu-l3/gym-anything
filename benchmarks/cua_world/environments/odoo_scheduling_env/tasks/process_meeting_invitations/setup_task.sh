#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up task: process_meeting_invitations ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Launch Firefox to ensure it's ready (but we'll navigate specifically after data injection)
ensure_firefox "about:blank"

# 2. Inject the specific meeting invitations for Next Wednesday
# We use Python to calculate "Next Wednesday" relative to today
python3 << PYTHON_EOF
import xmlrpc.client
import datetime
import sys
from datetime import timedelta

url = '$ODOO_URL'
db = '$ODOO_DB'
username = '$ODOO_USER'
password = '$ODOO_PASSWORD'

try:
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, username, password, {})
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')

    # Calculate Next Wednesday
    today = datetime.datetime.now()
    days_ahead = (2 - today.weekday() + 7) % 7
    if days_ahead == 0:
        days_ahead = 7
    next_wednesday = today + timedelta(days=days_ahead)
    
    # Event 1: Project Alpha Sync (10:00 - 11:00)
    start_1 = next_wednesday.replace(hour=10, minute=0, second=0).strftime('%Y-%m-%d %H:%M:%S')
    stop_1 = next_wednesday.replace(hour=11, minute=0, second=0).strftime('%Y-%m-%d %H:%M:%S')
    
    # Check if exists and clean up (idempotency)
    existing = models.execute_kw(db, uid, password, 'calendar.event', 'search', 
        [[['name', 'in', ['Project Alpha Sync', 'Vendor Cold Call']]]])
    if existing:
        models.execute_kw(db, uid, password, 'calendar.event', 'unlink', [existing])

    # Create Event 1
    id1 = models.execute_kw(db, uid, password, 'calendar.event', 'create', [{
        'name': 'Project Alpha Sync',
        'start': start_1,
        'stop': stop_1,
        'description': 'Mandatory team synchronization for Project Alpha milestones.',
        'location': 'Conference Room B'
    }])
    
    # Event 2: Vendor Cold Call (11:00 - 11:30)
    start_2 = next_wednesday.replace(hour=11, minute=0, second=0).strftime('%Y-%m-%d %H:%M:%S')
    stop_2 = next_wednesday.replace(hour=11, minute=30, second=0).strftime('%Y-%m-%d %H:%M:%S')
    
    # Create Event 2
    id2 = models.execute_kw(db, uid, password, 'calendar.event', 'create', [{
        'name': 'Vendor Cold Call',
        'start': start_2,
        'stop': stop_2,
        'description': 'Introduction to new office supply catalog.',
        'location': 'Online'
    }])
    
    # Force attendee status to 'needsAction' for the admin user
    # Get Admin partner ID
    user_data = models.execute_kw(db, uid, password, 'res.users', 'read', [uid], {'fields': ['partner_id']})
    partner_id = user_data[0]['partner_id'][0]
    
    # Find attendees linked to these events for this partner
    attendees = models.execute_kw(db, uid, password, 'calendar.attendee', 'search', 
        [[['event_id', 'in', [id1, id2]], ['partner_id', '=', partner_id]]])
        
    # Write state = needsAction
    if attendees:
        models.execute_kw(db, uid, password, 'calendar.attendee', 'write', [attendees, {'state': 'needsAction'}])
    
    # Save IDs for export script to use later
    with open('/tmp/task_event_ids.txt', 'w') as f:
        f.write(f"{id1}\n{id2}")
        
    print(f"Created events {id1} (Alpha) and {id2} (Vendor) on {next_wednesday.date()}")

except Exception as e:
    print(f"Error injecting data: {e}", file=sys.stderr)
    sys.exit(1)
PYTHON_EOF

# 3. Setup UI
# Navigate to Calendar
navigate_firefox "http://localhost:8069/web#action=calendar.action_calendar_event"

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="