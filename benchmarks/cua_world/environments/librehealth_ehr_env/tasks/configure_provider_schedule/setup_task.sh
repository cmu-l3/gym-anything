#!/bin/bash
set -e
echo "=== Setting up Configure Provider Schedule Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure LibreHealth is running
wait_for_librehealth 60

# 1. Create the provider 'Dr. Stephen Strange' if he doesn't exist
# We use a raw SQL insert for speed. Password hash is for 'password'
# Note: groups table linking might be needed for him to show up in calendar lists,
# usually 'Provider' group is id 3 or similar.
echo "Creating provider Dr. Stephen Strange..."

# Check if user exists
USER_EXISTS=$(librehealth_query "SELECT count(*) FROM users WHERE username='dr_strange'")

if [ "$USER_EXISTS" -eq "0" ]; then
    # Insert user (simplified, might need valid password hash if we were logging in as him, 
    # but we login as admin so just needs to exist for scheduling)
    librehealth_query "INSERT INTO users (username, password, authorized, fname, lname, active, facility_id) VALUES ('dr_strange', 'xxx', 1, 'Stephen', 'Strange', 1, 3)"
    
    # Get the ID
    NEW_ID=$(librehealth_query "SELECT id FROM users WHERE username='dr_strange'")
    
    # Add to 'Physician' group (often group_id 3 or 4 in defaults, ensuring he appears in provider lists)
    librehealth_query "INSERT INTO users_secure (id, username, password, salt, last_update, password_history1) VALUES ($NEW_ID, 'dr_strange', 'xxx', 'xxx', NOW(), '')" 2>/dev/null || true
else
    echo "User dr_strange already exists."
fi

STRANGE_ID=$(librehealth_query "SELECT id FROM users WHERE username='dr_strange'")
echo "Dr. Strange User ID: $STRANGE_ID"
echo "$STRANGE_ID" > /tmp/dr_strange_id.txt

# 2. Clean up any existing calendar events for this user to ensure a fresh start
echo "Clearing existing calendar events for Dr. Strange..."
librehealth_query "DELETE FROM openemr_postcalendar_events WHERE pc_aid = $STRANGE_ID"

# 3. Verify clean state
INITIAL_COUNT=$(librehealth_query "SELECT COUNT(*) FROM openemr_postcalendar_events WHERE pc_aid = $STRANGE_ID")
echo "Initial event count: $INITIAL_COUNT"
echo "$INITIAL_COUNT" > /tmp/initial_event_count.txt

# 4. Launch Firefox at Login
restart_firefox "http://localhost:8000/interface/login/login.php?site=default"

# Capture initial state
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="