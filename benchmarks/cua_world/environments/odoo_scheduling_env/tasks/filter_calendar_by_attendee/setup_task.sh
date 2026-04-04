#!/bin/bash
echo "=== Setting up filter_calendar_by_attendee task ==="

source /workspace/scripts/task_utils.sh

record_task_baseline "filter_calendar_by_attendee"

# Navigate to Calendar (no specific data setup needed; Alice Johnson is already an attendee
# on 'Q2 Financial Review' from setup_data.py)
ensure_firefox "http://localhost:8069/web#action=calendar.action_calendar_event"
navigate_firefox "http://localhost:8069/web#action=calendar.action_calendar_event"
sleep 3

take_screenshot /tmp/task_start.png

echo "Task start state: Odoo Calendar is shown with all events."
echo "Agent should use the attendee filter to show only Alice Johnson's events."
echo "=== filter_calendar_by_attendee task setup complete ==="
