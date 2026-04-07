#!/bin/bash
# Setup: create_encounter_role task
# Ensures the "Medical Scribe" role does NOT exist before starting.

echo "=== Setting up create_encounter_role task ==="
source /workspace/scripts/task_utils.sh

# Record task start time (anti-gaming)
date +%s > /tmp/task_start_timestamp

# Check if role exists and delete it if so
echo "Checking for existing 'Medical Scribe' role..."

# database query to find ID
ROLE_ID=$(omrs_db_query "SELECT encounter_role_id FROM encounter_role WHERE name = 'Medical Scribe'" 2>/dev/null)

if [ -n "$ROLE_ID" ]; then
    echo "Found existing role (ID: $ROLE_ID). Purging..."
    # We delete from DB directly to ensure clean slate for metadata
    omrs_db_query "DELETE FROM encounter_role WHERE encounter_role_id = $ROLE_ID"
    echo "Role deleted."
else
    echo "No existing role found. Clean state confirmed."
fi

# Ensure Admin is logged in and start on Home Page
# We start on Home so the agent has to navigate to Administration
ensure_openmrs_logged_in "http://localhost/openmrs/spa/home"

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo ""
echo "=== Setup Complete ==="
echo "Task: Create Encounter Role"
echo "Name: Medical Scribe"
echo "Desc: Assists with documentation"