#!/bin/bash
echo "=== Setting up Block Provider Schedule Task ==="

source /workspace/scripts/task_utils.sh

# Ensure LibreHealth EHR is running
wait_for_librehealth 60

# Record task start timestamp (for anti-gaming)
date +%s > /tmp/task_start_time.txt

# Record initial event count for today to detect changes
# Querying openemr_postcalendar_events
INITIAL_COUNT=$(librehealth_query "SELECT COUNT(*) FROM openemr_postcalendar_events WHERE pc_eventDate = CURDATE()" 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_event_count.txt
echo "Initial event count for today: $INITIAL_COUNT"

# Clean up any existing "Staff Meeting" events for today to ensure a clean slate
librehealth_query "DELETE FROM openemr_postcalendar_events WHERE pc_title LIKE '%Staff Meeting%' AND pc_eventDate = CURDATE()" 2>/dev/null || true

# Open Firefox at the Calendar view
# The URL for the calendar is usually .../interface/main/calendar/index.php?module=PostCalendar&func=view
CALENDAR_URL="http://localhost:8000/interface/main/calendar/index.php?module=PostCalendar&func=view"

echo "Navigating to Calendar..."
restart_firefox "$CALENDAR_URL"

# Wait for page load
sleep 5

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task Setup Complete ==="
echo "Goal: Block 4:00 PM - 5:00 PM for 'Staff Meeting' (Non-patient event)"