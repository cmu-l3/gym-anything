#!/bin/bash
set -e
echo "=== Setting up task: Restore Archived Meeting ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Create the specific archived event for this task using Python/XML-RPC
# We save the ID to a file so we can verify the EXACT record was restored later
python3 << PYTHON_EOF
import xmlrpc.client, datetime, sys

url = 'http://localhost:8069'
db = 'odoo_scheduling'
username = 'admin'
password = 'admin'

try:
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, username, password, {})
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')

    # cleanup: remove any existing events with this name to ensure clean state
    existing_ids = models.execute_kw(db, uid, password, 'calendar.event', 'search', 
                                   [[['name', '=', 'Q3 Board Prep'], '|', ['active', '=', True], ['active', '=', False]]])
    if existing_ids:
        models.execute_kw(db, uid, password, 'calendar.event', 'unlink', [existing_ids])
        print(f"Cleaned up {len(existing_ids)} existing events.")

    # Calculate date: Next Wednesday at 14:00
    now = datetime.datetime.now()
    days_ahead = (2 - now.weekday() + 7) % 7
    if days_ahead == 0: days_ahead = 7
    next_wed = now + datetime.timedelta(days=days_ahead)
    
    start_time = next_wed.replace(hour=14, minute=0, second=0).strftime('%Y-%m-%d %H:%M:%S')
    stop_time = next_wed.replace(hour=15, minute=30, second=0).strftime('%Y-%m-%d %H:%M:%S')

    # Get partner IDs for attendees
    partners = models.execute_kw(db, uid, password, 'res.partner', 'search', 
                               [[['email', 'in', ['grace.patel@northbridge.org', 'henry.kim@northbridge.org']]]])
    
    # Create the event directly in ARCHIVED state (active=False)
    event_id = models.execute_kw(db, uid, password, 'calendar.event', 'create', [{
        'name': 'Q3 Board Prep',
        'start': start_time,
        'stop': stop_time,
        'partner_ids': [[6, 0, partners]],
        'description': 'CRITICAL: Review board deck slides 10-15 regarding acquisition targets.',
        'location': 'Board Room',
        'active': False  # This makes it archived/hidden
    }])
    
    print(f"Created archived event 'Q3 Board Prep' with ID: {event_id}")
    
    # Save the ID for the export script to verify
    with open('/tmp/target_event_id.txt', 'w') as f:
        f.write(str(event_id))

except Exception as e:
    print(f"Setup failed: {e}", file=sys.stderr)
    sys.exit(1)
PYTHON_EOF

# Ensure Firefox is running and navigated to Calendar
# We start at the standard calendar view where the event is HIDDEN
ensure_firefox "http://localhost:8069/web#action=calendar.action_calendar_event"

# Take initial screenshot (should show calendar WITHOUT the meeting)
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="