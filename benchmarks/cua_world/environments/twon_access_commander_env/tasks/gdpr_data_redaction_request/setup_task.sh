#!/bin/bash
echo "=== Setting up GDPR Data Redaction Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

# Wait for 2N Access Commander to be ready
wait_for_ac_demo

# Authenticate via API
ac_login

# Find Ingrid Sorensen in the pre-seeded data
echo "Locating target user (Ingrid Sorensen)..."
USER_JSON=$(ac_api GET "/users" | jq -c '.[] | select(.firstName=="Ingrid" and .lastName=="Sorensen")' | head -1)

if [ -z "$USER_JSON" ]; then
    echo "Warning: Ingrid Sorensen not found in seeded data. Creating her now..."
    CREATE_PAYLOAD='{"firstName":"Ingrid","lastName":"Sorensen","email":"i.sorensen@buildingtech.com","phone":"+1-312-555-0153","company":"BuildingTech Solutions","enabled":true}'
    CREATE_RESP=$(ac_api POST "/users" "$CREATE_PAYLOAD")
    USER_ID=$(echo "$CREATE_RESP" | jq -r '.id // .userId // empty' 2>/dev/null)
    echo "Created user with ID: $USER_ID"
else
    USER_ID=$(echo "$USER_JSON" | jq -r '.id')
    echo "Found user with ID: $USER_ID"
    
    # Reset her data to ensure a clean starting state
    RESET_PAYLOAD='{"firstName":"Ingrid","lastName":"Sorensen","email":"i.sorensen@buildingtech.com","phone":"+1-312-555-0153","enabled":true}'
    ac_api PUT "/users/$USER_ID" "$RESET_PAYLOAD" > /dev/null
fi

if [ -z "$USER_ID" ] || [ "$USER_ID" == "null" ]; then
    echo "ERROR: Failed to establish target user ID."
    exit 1
fi

# Save the exact internal ID for verification.
# The agent MUST edit this specific ID, not delete and create a new one.
echo "$USER_ID" > /tmp/target_user_id.txt

# Start Firefox and navigate to the users page
launch_firefox_to "${AC_URL}/#/users" 8

# Take initial state screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="