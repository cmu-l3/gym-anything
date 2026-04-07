#!/bin/bash
set -e
echo "=== Setting up create_multiday_workshop task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# Calculate "Upcoming Wednesday" for context (to help verification if needed later)
# We don't strictly need to tell the agent the date, just "upcoming Wednesday"
NEXT_WEDNESDAY=$(python3 -c "
from datetime import date, timedelta
today = date.today()
days_until_wed = (2 - today.weekday()) % 7
if days_until_wed == 0:
    days_until_wed = 7
next_wed = today + timedelta(days=days_until_wed)
print(next_wed.strftime('%Y-%m-%d'))
")
echo "Target start date (calculated): $NEXT_WEDNESDAY" > /tmp/target_start_date.txt

# Clean up any existing events with the target title to ensure fresh creation
python3 << 'PYTHON_EOF'
import xmlrpc.client, sys
url = 'http://localhost:8069'
db = 'odoo_scheduling'
try:
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, 'admin', 'admin', {})
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')
    
    # Search for and delete existing events
    domain = [[['name', 'ilike', 'DevOps Workshop']]]
    existing_ids = models.execute_kw(db, uid, 'admin', 'calendar.event', 'search', [domain])
    
    if existing_ids:
        models.execute_kw(db, uid, 'admin', 'calendar.event', 'unlink', [existing_ids])
        print(f"Cleaned up {len(existing_ids)} existing workshop events.")
    else:
        print("No existing workshop events found.")

except Exception as e:
    print(f"Setup warning: {e}", file=sys.stderr)
PYTHON_EOF

# Record baseline event count
count_calendar_events > /tmp/initial_event_count.txt

# Ensure Firefox is running and navigated to the Calendar
ensure_firefox "http://localhost:8069/web#action=calendar.action_calendar_event&view_type=week"

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="