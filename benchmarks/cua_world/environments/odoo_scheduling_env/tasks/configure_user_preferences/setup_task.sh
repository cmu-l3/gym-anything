#!/bin/bash
set -e
echo "=== Setting up configure_user_preferences task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Configure the initial state of the admin user
# We must ensure the current state is NOT the target state to verify the agent actually does work.
python3 << 'PYTHON_EOF'
import xmlrpc.client
import json
import sys

url = 'http://localhost:8069'
db = 'odoo_scheduling'
username = 'admin'
password = 'admin'

try:
    # Authenticate
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, username, password, {})
    
    if not uid:
        print("Authentication failed", file=sys.stderr)
        sys.exit(1)

    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')

    # Read current preferences
    user_data = models.execute_kw(db, uid, password, 'res.users', 'read', [[uid]], 
                                {'fields': ['tz', 'notification_type']})
    
    current_tz = user_data[0].get('tz')
    current_notif = user_data[0].get('notification_type')
    
    print(f"Current state: tz={current_tz}, notif={current_notif}")

    updates = {}
    
    # If Timezone is already America/Chicago, reset it to UTC or something else
    if current_tz == 'America/Chicago':
        updates['tz'] = 'UTC'
        print("Resetting Timezone to UTC")

    # If Notification is already 'email', reset it to 'inbox' (Handle in Odoo)
    if current_notif == 'email':
        updates['notification_type'] = 'inbox'
        print("Resetting Notification to 'inbox'")
        
    # Apply resets if needed
    if updates:
        models.execute_kw(db, uid, password, 'res.users', 'write', [[uid], updates])
        # Re-read to confirm baseline
        user_data = models.execute_kw(db, uid, password, 'res.users', 'read', [[uid]], 
                                    {'fields': ['tz', 'notification_type']})
        
    # Save baseline to file for verification
    baseline = {
        'tz': user_data[0].get('tz'),
        'notification_type': user_data[0].get('notification_type')
    }
    
    with open('/tmp/user_prefs_baseline.json', 'w') as f:
        json.dump(baseline, f)
        
    print(f"Baseline recorded: {baseline}")

except Exception as e:
    print(f"Setup error: {e}", file=sys.stderr)
    sys.exit(1)
PYTHON_EOF

# Launch Firefox and log in (standard Odoo setup)
# We start at the Calendar view, agent must navigate to Preferences
ensure_firefox "http://localhost:8069/web#action=calendar.action_calendar_event"

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="