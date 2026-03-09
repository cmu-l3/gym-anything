#!/bin/bash
echo "=== Setting up schedule_calendar_event task ==="

source /workspace/scripts/task_utils.sh

# 1. Record initial event count
INITIAL_EVENT_COUNT=$(get_event_count)
echo "Initial event count: $INITIAL_EVENT_COUNT"
rm -f /tmp/initial_event_count.txt 2>/dev/null || true
echo "$INITIAL_EVENT_COUNT" > /tmp/initial_event_count.txt
chmod 666 /tmp/initial_event_count.txt 2>/dev/null || true

# 2. Verify the target event does not already exist
EXISTING=$(vtiger_db_query "SELECT activityid FROM vtiger_activity WHERE subject='GreenLeaf IoT Pilot Kickoff Meeting' LIMIT 1" | tr -d '[:space:]')
if [ -n "$EXISTING" ]; then
    echo "WARNING: Event already exists, removing"
    vtiger_db_query "DELETE FROM vtiger_crmentity WHERE crmid=$EXISTING"
    vtiger_db_query "DELETE FROM vtiger_activity WHERE activityid=$EXISTING"
fi

# 3. Ensure logged in and navigate to Calendar list
ensure_vtiger_logged_in "http://localhost:8000/index.php?module=Calendar&view=List"
sleep 3

# 5. Take initial screenshot
take_screenshot /tmp/schedule_event_initial.png

echo "=== schedule_calendar_event task setup complete ==="
echo "Task: Schedule meeting 'GreenLeaf IoT Pilot Kickoff Meeting'"
echo "Agent should create a new calendar event and fill in the form"
