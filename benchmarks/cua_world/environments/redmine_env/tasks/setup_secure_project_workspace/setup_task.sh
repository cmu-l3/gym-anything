#!/bin/bash
set -euo pipefail
echo "=== Setting up setup_secure_project_workspace task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Ensure Redmine is reachable
wait_for_http "$REDMINE_LOGIN_URL" 600

# Get a random user from the seed result to act as the HR Manager
# We pick a user that is NOT the admin and has a login
if [ -f "$SEED_RESULT_FILE" ]; then
    # Select the 2nd or 3rd user to ensure it's not admin (usually index 0 or 1)
    MANAGER_LOGIN=$(jq -r '.users[2].login // .users[1].login // empty' "$SEED_RESULT_FILE")
    
    if [ -z "$MANAGER_LOGIN" ]; then
        echo "WARNING: Could not extract user from seed file, falling back to 'admin'"
        MANAGER_LOGIN="admin"
    fi
else
    echo "WARNING: Seed file not found, defaulting to 'admin'"
    MANAGER_LOGIN="admin"
fi

# Write the target manager login to the file for the agent
echo "$MANAGER_LOGIN" > /home/ga/hr_manager_login.txt
chown ga:ga /home/ga/hr_manager_login.txt
chmod 644 /home/ga/hr_manager_login.txt

echo "Target Manager Login: $MANAGER_LOGIN"

# Ensure the project 'hr-cases' does not already exist
# We use the admin API key to check and delete if necessary
API_KEY=$(redmine_admin_api_key)
if [ -n "$API_KEY" ]; then
    echo "Checking if project 'hr-cases' exists..."
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -H "X-Redmine-API-Key: $API_KEY" "$REDMINE_BASE_URL/projects/hr-cases.json")
    
    if [ "$HTTP_CODE" = "200" ]; then
        echo "Project exists. Deleting..."
        curl -s -X DELETE -H "X-Redmine-API-Key: $API_KEY" "$REDMINE_BASE_URL/projects/hr-cases.json"
        sleep 2
    fi
fi

# Log in as admin and prepare browser
if ! ensure_redmine_logged_in "$REDMINE_BASE_URL/projects"; then
    echo "ERROR: Failed to log in to Redmine"
    exit 1
fi

# Capture initial state
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="