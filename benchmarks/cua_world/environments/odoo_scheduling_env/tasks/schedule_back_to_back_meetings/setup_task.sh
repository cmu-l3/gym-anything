#!/bin/bash
echo "=== Setting up schedule_back_to_back_meetings task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

# Record initial event count
INITIAL_COUNT=$(count_calendar_events)
echo "$INITIAL_COUNT" > /tmp/initial_event_count.txt
echo "Initial calendar event count: $INITIAL_COUNT"

# Calculate the target date (Wednesday of next week) for verification purposes
# We save this to a file so the export script knows exactly which date to check
python3 << 'PYEOF'
from datetime import datetime, timedelta
now = datetime.now()
# Calculate days until next Monday (1=Tue...7=Mon)
days_to_monday = (7 - now.weekday()) % 7 or 7
next_monday = now + timedelta(days=days_to_monday)
# Wednesday is 2 days after Monday
target_wednesday = next_monday + timedelta(days=2)
target_date_str = target_wednesday.strftime('%Y-%m-%d')

with open('/tmp/target_date.txt', 'w') as f:
    f.write(target_date_str)
print(f"Calculated target Wednesday: {target_date_str}")
PYEOF

# Ensure Firefox is running and navigated to the Calendar
# We use week view to make it easier for the agent to see slots
ensure_firefox "http://localhost:8069/web#action=calendar.action_calendar_event&view_type=week"

sleep 5

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="