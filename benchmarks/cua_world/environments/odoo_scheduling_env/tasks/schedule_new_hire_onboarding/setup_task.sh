#!/bin/bash
set -e
echo "=== Setting up schedule_new_hire_onboarding task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

# Calculate "Friday of next week" for logging/context
# Logic: Next Monday + 4 days
TARGET_FRIDAY=$(python3 -c "
from datetime import date, timedelta
today = date.today()
days_until_monday = (7 - today.weekday()) % 7 or 7
next_monday = today + timedelta(days=days_until_monday)
target_friday = next_monday + timedelta(days=4)
print(target_friday.strftime('%Y-%m-%d'))
")

echo "Target Date (Friday of next week): $TARGET_FRIDAY"

# Ensure Firefox is running and logged in, starting at the Calendar
ensure_firefox "http://localhost:8069/web#action=calendar.action_calendar_event"

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="