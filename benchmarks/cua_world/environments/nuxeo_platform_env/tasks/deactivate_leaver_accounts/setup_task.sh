#!/bin/bash
# Pre-task setup for deactivate_leaver_accounts
# Creates target users and the instruction note, then opens browser.

set -e
echo "=== Setting up Deactivate Leaver Accounts task ==="

source /workspace/scripts/task_utils.sh

# 1. Wait for Nuxeo to be fully ready
wait_for_nuxeo 120

# 2. Create the Users to be managed
echo "Creating target users..."

create_user() {
    local username="$1"
    local firstname="$2"
    local lastname="$3"
    
    # Check if user exists
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -u "$NUXEO_AUTH" "$NUXEO_URL/api/v1/user/$username")
    
    if [ "$HTTP_CODE" != "200" ]; then
        echo "  Creating user: $username"
        curl -s -u "$NUXEO_AUTH" \
            -H "Content-Type: application/json" \
            -X POST "$NUXEO_URL/api/v1/user" \
            -d "{
                \"entity-type\": \"user\",
                \"id\": \"$username\",
                \"properties\": {
                    \"username\": \"$username\",
                    \"firstName\": \"$firstname\",
                    \"lastName\": \"$lastname\",
                    \"email\": \"$username@example.com\",
                    \"password\": \"password123\",
                    \"groups\": [\"members\"]
                }
            }" > /dev/null
    else
        echo "  User $username already exists."
    fi
}

create_user "mholloway" "Marcus" "Holloway"
create_user "clille" "Clara" "Lille"
create_user "sdhawan" "Sitara" "Dhawan"

# 3. Create the Instruction Note in Projects workspace
echo "Creating instruction note..."

NOTE_TITLE="Access Termination Request"
NOTE_NAME="Access-Termination-Request"
NOTE_CONTENT="<p><strong>Subject: Offboarding List - Oct 2023</strong></p><p>Please process the following account terminations effective immediately:</p><ul><li>Marcus Holloway (username: <strong>mholloway</strong>) - Contract Completed</li><li>Clara Lille (username: <strong>clille</strong>) - Resigned</li></ul><p><strong>UPDATE:</strong> Sitara Dhawan (username: <strong>sdhawan</strong>) has extended her contract. Do <strong>NOT</strong> remove her access yet.</p><p>Thanks,<br>HR Dept</p>"

# Check if note exists
NOTE_CODE=$(curl -s -o /dev/null -w "%{http_code}" -u "$NUXEO_AUTH" "$NUXEO_URL/api/v1/path/default-domain/workspaces/Projects/$NOTE_NAME")

if [ "$NOTE_CODE" != "200" ]; then
    # Create the note
    PAYLOAD=$(cat <<EOF
{
  "entity-type": "document",
  "type": "Note",
  "name": "$NOTE_NAME",
  "properties": {
    "dc:title": "$NOTE_TITLE",
    "note:note": "$NOTE_CONTENT",
    "dc:description": "HR request for user account processing"
  }
}
EOF
)
    nuxeo_api POST "/path/default-domain/workspaces/Projects" "$PAYLOAD" > /dev/null
    echo "  Created note: $NOTE_NAME"
else
    # Update existing note to ensure content is correct (idempotency)
    PAYLOAD=$(cat <<EOF
{
  "entity-type": "document",
  "properties": {
    "note:note": "$NOTE_CONTENT",
    "dc:title": "$NOTE_TITLE"
  }
}
EOF
)
    nuxeo_api PUT "/path/default-domain/workspaces/Projects/$NOTE_NAME" "$PAYLOAD" > /dev/null
    echo "  Updated note: $NOTE_NAME"
fi

# 4. Prepare Browser
# Kill any existing instances
pkill -f firefox 2>/dev/null || true
sleep 1

# Start Firefox and login
# We start at the Login page, then the script below logs in
open_nuxeo_url "$NUXEO_URL/login.jsp" 8

# Automate login
nuxeo_login

# Navigate to Projects workspace so the agent sees the note immediately
navigate_to "$NUXEO_UI/#!/browse/default-domain/workspaces/Projects"

# 5. Record Initial State
date +%s > /tmp/task_start_time.txt

# Maximize window one last time to be sure
DISPLAY=:1 wmctrl -r "Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Initial screenshot
echo "Capturing initial state..."
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task Setup Complete ==="