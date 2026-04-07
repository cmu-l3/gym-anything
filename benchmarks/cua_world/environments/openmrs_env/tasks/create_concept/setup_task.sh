#!/bin/bash
# Setup: create_concept task
# Ensures "Toluene Exposure" does not currently exist as an active concept.
# If it exists, it renames and retires it to free up the name.

echo "=== Setting up create_concept task ==="
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Check for existing concept "Toluene Exposure"
echo "Checking for existing concept 'Toluene Exposure'..."

# We use a DB query to find the concept ID of any active concept with this name
EXISTING_ID=$(omrs_db_query "SELECT c.concept_id FROM concept c JOIN concept_name cn ON c.concept_id = cn.concept_id WHERE cn.name = 'Toluene Exposure' AND c.retired = 0 LIMIT 1;")

if [ -n "$EXISTING_ID" ] && [ "$EXISTING_ID" != "0" ]; then
    echo "Found existing active concept ID: $EXISTING_ID. Archiving..."
    
    # Generate a timestamped suffix
    SUFFIX=$(date +%s)
    
    # Rename the concept name to free up "Toluene Exposure"
    omrs_db_query "UPDATE concept_name SET name = CONCAT(name, ' (Archived $SUFFIX)') WHERE concept_id = $EXISTING_ID;"
    
    # Retire the concept
    omrs_db_query "UPDATE concept SET retired = 1, retire_reason = 'Task Setup Cleanup' WHERE concept_id = $EXISTING_ID;"
    
    echo "Existing concept archived and retired."
else
    echo "No conflict found."
fi

# 2. Open Firefox on the Home Page or Advanced Admin page
# The user needs to find the Dictionary, usually under "System Administration" or Legacy Admin
HOME_URL="http://localhost/openmrs/spa/home"

# Ensure logged in
ensure_openmrs_logged_in "$HOME_URL"

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="
echo "Target Concept: Toluene Exposure"
echo "Target Class: Diagnosis"
echo "Target Datatype: N/A"