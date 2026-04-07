#!/bin/bash
echo "=== Setting up complete_post_meeting_workflow task ==="

# Source shared utilities for SuiteCRM
source /workspace/scripts/task_utils.sh

# Record task start time for verification
date +%s > /tmp/task_start_time.txt

# 1. Clean up any existing meeting with our specific testing ID or Name to ensure a clean state
echo "Preparing database state..."
suitecrm_db_query "DELETE FROM meetings WHERE id='meeting-q3-sync-0001';"
suitecrm_db_query "UPDATE meetings SET deleted=1 WHERE name='Global Widgets - Q3 Roadmap Sync';"
suitecrm_db_query "UPDATE notes SET deleted=1 WHERE name='Q3 Roadmap Sync - Minutes';"
suitecrm_db_query "UPDATE tasks SET deleted=1 WHERE name='Draft Q3 SLA Addendum';"

# 2. Insert the target meeting that the agent needs to update
# We use a hardcoded UUID so it's strictly identifiable by the verifier
echo "Inserting target 'Planned' meeting..."
suitecrm_db_query "INSERT INTO meetings (id, name, date_entered, date_modified, modified_user_id, created_by, description, deleted, status, date_start, date_end, duration_hours, duration_minutes) VALUES ('meeting-q3-sync-0001', 'Global Widgets - Q3 Roadmap Sync', UTC_TIMESTAMP(), UTC_TIMESTAMP(), '1', '1', 'Q3 planning sync with primary contact at Global Widgets.', 0, 'Planned', DATE_ADD(UTC_TIMESTAMP(), INTERVAL -1 DAY), DATE_ADD(UTC_TIMESTAMP(), INTERVAL -23 HOUR), 1, 0);"

# Verify insertion
MEETING_EXISTS=$(suitecrm_db_query "SELECT COUNT(*) FROM meetings WHERE id='meeting-q3-sync-0001' AND deleted=0" | tr -d '[:space:]')
if [ "$MEETING_EXISTS" -eq 1 ]; then
    echo "Target meeting successfully created."
else
    echo "WARNING: Failed to insert target meeting!"
fi

# 3. Ensure logged in and navigate to the Meetings list view
echo "Navigating to SuiteCRM Meetings list..."
ensure_suitecrm_logged_in "http://localhost:8000/index.php?module=Meetings&action=index"
sleep 5

# 4. Take initial state screenshot
echo "Capturing initial screenshot..."
take_screenshot /tmp/task_initial.png

echo "=== complete_post_meeting_workflow task setup complete ==="
echo "Task: Complete post-meeting workflow for 'Global Widgets - Q3 Roadmap Sync'"