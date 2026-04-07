#!/bin/bash
set -e
echo "=== Setting up schedule_overnight_event task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Record baseline state (count of events)
INITIAL_COUNT=$(count_calendar_events)
echo "$INITIAL_COUNT" > /tmp/initial_count.txt

# Remove any existing 'Database Migration' events to ensure clean state
python3 << 'PYTHON_EOF'
import xmlrpc.client, sys
url = 'http://localhost:8069'
db = 'odoo_scheduling'
try:
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, 'admin', 'admin', {})
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')
    
    # Search for existing events with the same name
    existing = models.execute_kw(db, uid, 'admin', 'calendar.event', 'search',
                                 [[['name', '=', 'Database Migration']]])
    
    if existing:
        models.execute_kw(db, uid, 'admin', 'calendar.event', 'unlink', [existing])
        print(f"Cleaned up {len(existing)} existing 'Database Migration' events.")
except Exception as e:
    print(f"Cleanup warning: {e}", file=sys.stderr)
PYTHON_EOF

# Calculate dates for the agent's context
# "Friday of next week" means the Friday of the week starting next Monday
DATES_INFO=$(python3 << 'PYTHON_EOF'
from datetime import datetime, timedelta
now = datetime.now()
# Calculate next Monday
days_ahead = 7 - now.weekday()
if days_ahead <= 0: # Target Monday is in future
    days_ahead += 7
next_monday = now + timedelta(days=days_ahead)
# Target Friday is 4 days after next Monday
target_friday = next_monday + timedelta(days=4)
target_saturday = target_friday + timedelta(days=1)

print(f"TARGET_FRIDAY_DATE='{target_friday.strftime('%Y-%m-%d')}'")
print(f"TARGET_FRIDAY_DISPLAY='{target_friday.strftime('%A, %B %d, %Y')}'")
print(f"TARGET_SATURDAY_DISPLAY='{target_saturday.strftime('%A, %B %d, %Y')}'")
PYTHON_EOF
)

eval "$DATES_INFO"

# Ensure Firefox is running and logged in
ensure_firefox "http://localhost:8069/web#action=calendar.action_calendar_event"

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task Setup Complete ==="
echo "Target Date: $TARGET_FRIDAY_DISPLAY"
echo "Instructions:"
echo "1. Create event 'Database Migration'"
echo "2. Start: $TARGET_FRIDAY_DISPLAY at 11:00 PM"
echo "3. End: $TARGET_SATURDAY_DISPLAY at 3:00 AM"
echo "4. Location: Server Room"