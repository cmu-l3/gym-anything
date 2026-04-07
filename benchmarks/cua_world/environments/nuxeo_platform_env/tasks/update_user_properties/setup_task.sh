#!/bin/bash
# Setup script for update_user_properties task
# Ensures jsmith exists with known INITIAL values, then opens the Nuxeo Web UI.

set -e
echo "=== Setting up update_user_properties task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (anti-gaming)
date +%s > /tmp/task_start_time.txt

# Wait for Nuxeo to be available
wait_for_nuxeo 120

# ---------------------------------------------------------------------------
# Step 1: Ensure user jsmith exists with known INITIAL properties
# ---------------------------------------------------------------------------
echo "Ensuring user jsmith exists with baseline properties..."

# Create or reset jsmith to initial state via API
# We use curl directly here to ensure exact state
curl -s -u "$NUXEO_AUTH" \
    -H "Content-Type: application/json" \
    -X POST "$NUXEO_URL/api/v1/user" \
    -d '{
        "entity-type": "user",
        "id": "jsmith",
        "properties": {
            "username": "jsmith",
            "firstName": "John",
            "lastName": "Smith",
            "email": "jsmith@acmecorp.com",
            "company": "Acme Corp",
            "password": "jsmith123",
            "groups": ["members"]
        }
    }' > /dev/null 2>&1 || \
curl -s -u "$NUXEO_AUTH" \
    -H "Content-Type: application/json" \
    -X PUT "$NUXEO_URL/api/v1/user/jsmith" \
    -d '{
        "entity-type": "user",
        "id": "jsmith",
        "properties": {
            "username": "jsmith",
            "firstName": "John",
            "lastName": "Smith",
            "email": "jsmith@acmecorp.com",
            "company": "Acme Corp",
            "password": "jsmith123",
            "groups": ["members"]
        }
    }' > /dev/null

echo "User jsmith reset to initial state."

# ---------------------------------------------------------------------------
# Step 2: Ensure powerusers group exists
# ---------------------------------------------------------------------------
PU_CODE=$(curl -s -o /dev/null -w "%{http_code}" -u "$NUXEO_AUTH" \
    "$NUXEO_URL/api/v1/group/powerusers")
if [ "$PU_CODE" != "200" ]; then
    echo "Creating powerusers group..."
    curl -s -u "$NUXEO_AUTH" \
        -H "Content-Type: application/json" \
        -X POST "$NUXEO_URL/api/v1/group" \
        -d '{
            "entity-type": "group",
            "groupname": "powerusers",
            "grouplabel": "Power Users",
            "memberUsers": [],
            "memberGroups": []
        }' > /dev/null
fi

# ---------------------------------------------------------------------------
# Step 3: Record initial state for verification comparison
# ---------------------------------------------------------------------------
curl -s -u "$NUXEO_AUTH" "$NUXEO_URL/api/v1/user/jsmith" > /tmp/initial_jsmith_state.json

# ---------------------------------------------------------------------------
# Step 4: Open Firefox and login to Nuxeo Web UI
# ---------------------------------------------------------------------------
echo "Opening Firefox with Nuxeo Web UI..."
# Open login page first
open_nuxeo_url "$NUXEO_URL/login.jsp" 8

# Check if we need to login
PAGE_TITLE=$(DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority \
    xdotool getactivewindow getwindowname 2>/dev/null || echo "")

if ! echo "$PAGE_TITLE" | grep -q " - Nuxeo Platform"; then
    nuxeo_login
fi

# Navigate to the Administration home or Dashboard to start
navigate_to "$NUXEO_UI/#!/doc/default-domain"
sleep 2

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="