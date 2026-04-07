#!/bin/bash
set -e
echo "=== Setting up rename_calendar_event task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Reset the specific event to its initial state using Python/XML-RPC
# This ensures the task is repeatable even if the agent messed it up previously
python3 << 'PYTHON_EOF'
import xmlrpc.client
import sys
import datetime

url = 'http://localhost:8069'
db = 'odoo_scheduling'
username = 'admin'
password = 'admin'

try:
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, username, password, {})
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')

    # 1. Check for the TARGET name and revert it if found (cleanup from previous run)
    target_name = "Q3 Marketing Results & Q4 Strategy Planning"
    target_events = models.execute_kw(db, uid, password, 'calendar.event', 'search',
                                    [[['name', '=', target_name]]])
    if target_events:
        print(f"Cleaning up {len(target_events)} events with target name...")
        # We delete them to avoid confusion, or rename them back if we want to be fancy.
        # Deleting is safer to ensure we start clean.
        models.execute_kw(db, uid, password, 'calendar.event', 'unlink', [target_events])

    # 2. Ensure the ORIGINAL event exists with correct properties
    original_name = "Marketing Campaign Review"
    
    # Search for existing original event
    original_events = models.execute_kw(db, uid, password, 'calendar.event', 'search',
                                      [[['name', '=', original_name]]])
    
    # Get partner IDs for attendees
    alice_id = models.execute_kw(db, uid, password, 'res.partner', 'search', [[['name', '=', 'Alice Johnson']]])
    carol_id = models.execute_kw(db, uid, password, 'res.partner', 'search', [[['name', '=', 'Carol Martinez']]])
    
    attendee_ids = []
    if alice_id: attendee_ids.append(alice_id[0])
    if carol_id: attendee_ids.append(carol_id[0])

    # Calculate time (next Tuesday 14:00)
    today = datetime.datetime.now()
    days_ahead = (1 - today.weekday() + 7) % 7 + 7  # Next Tuesday
    if days_ahead < 7: days_ahead += 7
    event_start = (today + datetime.timedelta(days=days_ahead)).replace(hour=14, minute=0, second=0).strftime('%Y-%m-%d %H:%M:%S')
    event_stop = (today + datetime.timedelta(days=days_ahead)).replace(hour=15, minute=0, second=0).strftime('%Y-%m-%d %H:%M:%S')

    event_vals = {
        'name': original_name,
        'location': 'Zoom Meeting',
        'description': 'Review Q3 marketing campaign results and plan Q4 strategy.',
        'start': event_start,
        'stop': event_stop,
        'partner_ids': [[6, 0, attendee_ids]] # Set M2M field
    }

    if original_events:
        # Reset existing event
        print(f"Resetting existing event ID {original_events[0]}...")
        models.execute_kw(db, uid, password, 'calendar.event', 'write', [original_events, event_vals])
        event_id = original_events[0]
    else:
        # Create new event
        print("Creating new event...")
        event_id = models.execute_kw(db, uid, password, 'calendar.event', 'create', [event_vals])
    
    # Save the event ID to a file for verification correlation
    with open('/tmp/target_event_id.txt', 'w') as f:
        f.write(str(event_id))
        
    print(f"Setup complete. Event ID: {event_id}")

except Exception as e:
    print(f"Setup failed: {e}", file=sys.stderr)
    sys.exit(1)
PYTHON_EOF

# Ensure Firefox is open and navigated to Calendar
ensure_firefox "http://localhost:8069/web#action=calendar.action_calendar_event&view_type=calendar"

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="