#!/bin/bash
echo "=== Setting up schedule_recurring_meeting task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time (anti-gaming)
date +%s > /tmp/task_start_time.txt

# Create "Apex Distributors" account if it doesn't exist
ACCOUNT_EXISTS=$(suitecrm_db_query "SELECT COUNT(*) FROM accounts WHERE name='Apex Distributors' AND deleted=0")
if [ "$ACCOUNT_EXISTS" -eq 0 ]; then
    echo "Creating Apex Distributors account..."
    # Generate unique ID
    ACC_ID=$(cat /proc/sys/kernel/random/uuid)
    DATE_ENT=$(date -u +"%Y-%m-%d %H:%M:%S")
    suitecrm_db_query "INSERT INTO accounts (id, name, date_entered, date_modified, modified_user_id, created_by, deleted, assigned_user_id, account_type, industry) VALUES ('$ACC_ID', 'Apex Distributors', '$DATE_ENT', '$DATE_ENT', '1', '1', 0, '1', 'Customer', 'Distribution')"
fi

# Record initial meeting count
INITIAL_MEETING_COUNT=$(get_meeting_count)
echo "Initial meeting count: $INITIAL_MEETING_COUNT"
echo "$INITIAL_MEETING_COUNT" > /tmp/initial_meeting_count.txt
chmod 666 /tmp/initial_meeting_count.txt 2>/dev/null || true

# Verify the target meeting does not already exist
if meeting_exists "Pilot Status Sync"; then
    echo "WARNING: Meeting already exists, removing"
    soft_delete_record "meetings" "name='Pilot Status Sync'"
fi

# Ensure logged in and navigate to Meetings list
ensure_suitecrm_logged_in "http://localhost:8000/index.php?module=Meetings&action=index"
sleep 3

# Take initial screenshot
take_screenshot /tmp/schedule_recurring_meeting_initial.png

echo "=== schedule_recurring_meeting task setup complete ==="