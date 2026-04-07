#!/bin/bash
set -e
echo "=== Setting up create_user_group task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Wait for Nuxeo to be ready
wait_for_nuxeo 120

# --- Ensure user jsmith exists ---
JSMITH_CODE=$(curl -s -o /dev/null -w "%{http_code}" -u "$NUXEO_AUTH" \
    "$NUXEO_URL/api/v1/user/jsmith")
if [ "$JSMITH_CODE" != "200" ]; then
    echo "Creating user jsmith..."
    nuxeo_api POST "/user" '{
        "entity-type": "user",
        "id": "jsmith",
        "properties": {
            "username": "jsmith",
            "firstName": "John",
            "lastName": "Smith",
            "email": "jsmith@example.com",
            "password": "jsmith123",
            "groups": ["members"]
        }
    }' > /dev/null
    echo "User jsmith created."
else
    echo "User jsmith already exists."
fi

# --- Ensure user mwilson exists ---
MWILSON_CODE=$(curl -s -o /dev/null -w "%{http_code}" -u "$NUXEO_AUTH" \
    "$NUXEO_URL/api/v1/user/mwilson")
if [ "$MWILSON_CODE" != "200" ]; then
    echo "Creating user mwilson..."
    nuxeo_api POST "/user" '{
        "entity-type": "user",
        "id": "mwilson",
        "properties": {
            "username": "mwilson",
            "firstName": "Maria",
            "lastName": "Wilson",
            "email": "mwilson@example.com",
            "password": "mwilson123",
            "groups": ["members"]
        }
    }' > /dev/null
    echo "User mwilson created."
else
    echo "User mwilson already exists."
fi

# --- Delete compliance-team group if it exists (ensure clean state) ---
curl -s -o /dev/null -u "$NUXEO_AUTH" -X DELETE \
    "$NUXEO_URL/api/v1/group/compliance-team" 2>/dev/null || true

# Record initial state of the group (should be 404)
GROUP_CHECK=$(curl -s -o /dev/null -w "%{http_code}" -u "$NUXEO_AUTH" \
    "$NUXEO_URL/api/v1/group/compliance-team")
echo "$GROUP_CHECK" > /tmp/initial_group_state.txt
echo "Initial group state: HTTP $GROUP_CHECK (should be 404)"

# --- Open Firefox to Nuxeo Web UI admin page ---
# We use the base URL first to ensure login, then navigate
open_nuxeo_url "$NUXEO_URL/login.jsp" 8

# Check if login is needed
sleep 2
PAGE_TITLE=$(DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority \
    xdotool getactivewindow getwindowname 2>/dev/null || echo "")

if ! echo "$PAGE_TITLE" | grep -q " - Nuxeo Platform"; then
    nuxeo_login
fi

# Navigate specifically to the Users & Groups management area
# This puts the agent in the right context
navigate_to "$NUXEO_UI/#!/admin/user-group-management"
sleep 4

# Take initial screenshot for evidence
echo "Capturing initial state..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="