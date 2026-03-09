#!/bin/bash
echo "=== Setting up create_user task ==="

source /workspace/scripts/task_utils.sh

# Refresh auth token
refresh_nx_token > /dev/null 2>&1 || true

# Record initial user count for baseline
INITIAL_COUNT=$(count_users 2>/dev/null || echo "0")
echo "Initial user count: $INITIAL_COUNT"
echo "$INITIAL_COUNT" > /tmp/nx_initial_user_count.txt

# Remove 'mike.chen' user if it already exists (idempotent setup)
EXISTING_USER=$(get_user_by_name "mike.chen" 2>/dev/null || true)
if [ -n "$EXISTING_USER" ]; then
    EXISTING_ID=$(echo "$EXISTING_USER" | python3 -c "import sys,json; print(json.load(sys.stdin).get('id',''))" 2>/dev/null || true)
    if [ -n "$EXISTING_ID" ]; then
        echo "Removing existing user 'mike.chen' (id: $EXISTING_ID)"
        nx_api_delete "/rest/v1/users/${EXISTING_ID}" || true
        sleep 2
    fi
fi

# Ensure Firefox is running and on the Nx Witness Web Admin Users section
ensure_firefox_running "https://localhost:7001/static/index.html#/settings/users"
sleep 5
maximize_firefox

# Take initial screenshot for evidence
take_screenshot /tmp/nx_create_user_start.png

echo "=== create_user task setup complete ==="
echo "Task: Create user 'mike.chen' (Mike Chen) with role 'Viewer' via the Nx Witness Web Admin"
echo "Email: mike.chen@security.local"
echo "Password: SecureVMS2024!"
