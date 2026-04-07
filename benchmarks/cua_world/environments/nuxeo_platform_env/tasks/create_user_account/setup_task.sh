#!/bin/bash
set -e
echo "=== Setting up create_user_account task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Wait for Nuxeo to be ready
wait_for_nuxeo 120

echo "Cleaning up any previous run artifacts..."

# 1. Delete user 'mwilson' if exists
# We use the REST API for cleanup to ensure a clean state
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -u "$NUXEO_AUTH" "$NUXEO_URL/api/v1/user/mwilson")
if [ "$HTTP_CODE" = "200" ]; then
    echo "Removing existing user 'mwilson'..."
    curl -s -u "$NUXEO_AUTH" -X DELETE "$NUXEO_URL/api/v1/user/mwilson" > /dev/null
fi

# 2. Delete workspace 'Maria Wilson Files' if exists
# Note: Nuxeo generates the path ID from the title (Maria-Wilson-Files)
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -u "$NUXEO_AUTH" "$NUXEO_URL/api/v1/path/default-domain/workspaces/Maria-Wilson-Files")
if [ "$HTTP_CODE" = "200" ]; then
    echo "Removing existing workspace 'Maria Wilson Files'..."
    curl -s -u "$NUXEO_AUTH" -X DELETE "$NUXEO_URL/api/v1/path/default-domain/workspaces/Maria-Wilson-Files" > /dev/null
fi

# 3. Ensure 'members' group exists (it is a default group, but good to check)
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -u "$NUXEO_AUTH" "$NUXEO_URL/api/v1/group/members")
if [ "$HTTP_CODE" != "200" ]; then
    echo "Creating 'members' group..."
    curl -s -u "$NUXEO_AUTH" -H "Content-Type: application/json" \
        -X POST "$NUXEO_URL/api/v1/group/" \
        -d '{"entity-type":"group","groupname":"members","grouplabel":"Members"}' > /dev/null
fi

# 4. Prepare Browser
# Open Firefox to the login page
echo "Launching Firefox..."
open_nuxeo_url "$NUXEO_URL/login.jsp" 10

# Log in as Administrator
nuxeo_login

# Take initial screenshot for evidence
echo "Capturing initial state..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="