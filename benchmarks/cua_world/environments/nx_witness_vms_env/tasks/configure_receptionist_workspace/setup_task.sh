#!/bin/bash
set -e
echo "=== Setting up configure_receptionist_workspace task ==="

source /workspace/scripts/task_utils.sh

# Record start time
date +%s > /tmp/task_start_time.txt

# Refresh Token
refresh_nx_token > /dev/null 2>&1 || true

# ==============================================================================
# CLEANUP: Remove artifacts if they exist from previous runs
# ==============================================================================
echo "Cleaning up previous task artifacts..."

# 1. Delete User 'receptionist'
USER_ID=$(get_user_by_name "receptionist" | python3 -c "import sys,json; print(json.load(sys.stdin).get('id',''))" 2>/dev/null || true)
if [ -n "$USER_ID" ]; then
    echo "Deleting existing receptionist user..."
    nx_api_delete "/rest/v1/users/${USER_ID}" || true
fi

# 2. Delete Role 'Front Desk Role'
# Fetch all roles, find the one with the name, get ID
ROLES_JSON=$(nx_api_get "/rest/v1/userRoles")
ROLE_ID=$(echo "$ROLES_JSON" | python3 -c "
import sys, json
try:
    roles = json.load(sys.stdin)
    for r in roles:
        if r.get('name') == 'Front Desk Role':
            print(r.get('id'))
            break
except: pass" 2>/dev/null || true)

if [ -n "$ROLE_ID" ]; then
    echo "Deleting existing Front Desk Role..."
    nx_api_delete "/rest/v1/userRoles/${ROLE_ID}" || true
fi

# 3. Delete Layout 'Reception Desk View'
LAYOUT_ID=$(get_layout_by_name "Reception Desk View" | python3 -c "import sys,json; print(json.load(sys.stdin).get('id',''))" 2>/dev/null || true)
if [ -n "$LAYOUT_ID" ]; then
    echo "Deleting existing layout..."
    nx_api_delete "/rest/v1/layouts/${LAYOUT_ID}" || true
fi

# 4. Cleanup Event Rules (Soft Triggers) containing "Unlock Door" or "Panic Alert"
RULES_JSON=$(nx_api_get "/rest/v1/eventRules")
echo "$RULES_JSON" | python3 -c "
import sys, json
try:
    rules = json.load(sys.stdin)
    for r in rules:
        # Check for specific captions in softwareTrigger events
        if r.get('eventType') == 'softwareTrigger':
            caption = r.get('eventCondition', {}).get('params', {}).get('caption', '')
            if caption in ['Unlock Door', 'Panic Alert']:
                print(r.get('id'))
except: pass" | while read rule_id; do
    if [ -n "$rule_id" ]; then
        echo "Deleting existing event rule: $rule_id"
        nx_api_delete "/rest/v1/eventRules/${rule_id}" || true
    fi
done

# ==============================================================================
# ENVIRONMENT PREP
# ==============================================================================

# Ensure Firefox is running (Web Admin is good for User/Role management)
echo "Starting Firefox..."
ensure_firefox_running "https://localhost:7001/static/index.html#/settings/users"
maximize_firefox
sleep 2

# Launch Desktop Client (Good for Layouts/Soft Triggers)
# We launch it in background so agent has choice
echo "Launching Desktop Client..."
APPLAUNCHER=$(find /opt -name "applauncher" -type f 2>/dev/null | head -1)
if [ -n "$APPLAUNCHER" ]; then
    DISPLAY=:1 "$APPLAUNCHER" > /dev/null 2>&1 &
    sleep 10
    # Try to maximize if it appeared
    DISPLAY=:1 wmctrl -r "Nx Witness" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task Setup Complete ==="