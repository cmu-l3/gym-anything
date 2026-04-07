#!/bin/bash
set -e
echo "=== Setting up schedule_non_attending_meeting task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Calculate target date for context/verification
# Logic matches setup_data.py: Anchor to next Monday
TARGET_DATE_STR=$(python3 -c "
from datetime import datetime, timedelta
now = datetime.now()
days_to_monday = (7 - now.weekday()) % 7 or 7
next_monday = now + timedelta(days=days_to_monday)
target_thursday = next_monday + timedelta(days=3)
print(target_thursday.strftime('%Y-%m-%d'))
")
echo "Target Date (Next Thursday): $TARGET_DATE_STR" > /tmp/target_date.txt

# Clean up any existing event with the same name to ensure fresh creation
echo "Cleaning up existing events..."
python3 << PYTHON_EOF
import xmlrpc.client
url = '$ODOO_URL'
db = '$ODOO_DB'
username = '$ODOO_USER'
password = '$ODOO_PASSWORD'

try:
    common = xmlrpc.client.ServerProxy('{}/xmlrpc/2/common'.format(url))
    uid = common.authenticate(db, username, password, {})
    models = xmlrpc.client.ServerProxy('{}/xmlrpc/2/object'.format(url))
    
    # Search and delete
    ids = models.execute_kw(db, uid, password, 'calendar.event', 'search',
        [[['name', 'ilike', 'Executive Severance Review']]])
    
    if ids:
        models.execute_kw(db, uid, password, 'calendar.event', 'unlink', [ids])
        print(f"Deleted {len(ids)} existing event(s)")
except Exception as e:
    print(f"Cleanup error: {e}")
PYTHON_EOF

# Ensure Firefox is running and logged in
ensure_firefox "http://localhost:8069/web#action=calendar.action_calendar_event"

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="