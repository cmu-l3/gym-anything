#!/bin/bash
echo "=== Setting up schedule_meeting task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. Record initial meeting count
INITIAL_MEETING_COUNT=$(get_meeting_count)
echo "Initial meeting count: $INITIAL_MEETING_COUNT"
rm -f /tmp/initial_meeting_count.txt 2>/dev/null || true
echo "$INITIAL_MEETING_COUNT" > /tmp/initial_meeting_count.txt
chmod 666 /tmp/initial_meeting_count.txt 2>/dev/null || true

# 2. Verify the target meeting does not already exist
if meeting_exists "Adobe Creative Cloud Integration - Technical Architecture Review"; then
    echo "WARNING: Meeting already exists, removing"
    soft_delete_record "meetings" "name='Adobe Creative Cloud Integration - Technical Architecture Review'"
fi

# 3. Ensure logged in and navigate to Meetings list
ensure_suitecrm_logged_in "http://localhost:8000/index.php?module=Meetings&action=index"
sleep 3

# 4. Take initial screenshot
take_screenshot /tmp/schedule_meeting_initial.png

echo "=== schedule_meeting task setup complete ==="
echo "Task: Schedule a meeting for Adobe Creative Cloud integration review"
echo "Agent should click Schedule Meeting and fill in the form"
