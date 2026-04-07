#!/bin/bash
# Setup script for secure_folder_custom_acl task
# Ensures clean state: removes any prior Confidential-HR folder, verifies
# prerequisites, and opens Firefox to the Projects workspace.

set -e
echo "=== Setting up secure_folder_custom_acl task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# -----------------------------------------------------------------------
# Step 1: Wait for Nuxeo to be ready
# -----------------------------------------------------------------------
wait_for_nuxeo 120

# -----------------------------------------------------------------------
# Step 2: Clean up any existing Confidential-HR folder from prior runs
# -----------------------------------------------------------------------
echo "Cleaning up prior Confidential-HR folder if it exists..."
# Using HTTP 200 check to see if it exists before trying to delete
if doc_exists "/default-domain/workspaces/Projects/Confidential-HR"; then
    echo "  Folder exists, attempting deletion..."
    # Delete the folder via API
    nuxeo_api DELETE "/path/default-domain/workspaces/Projects/Confidential-HR" > /dev/null 2>&1 || true
    # Also try permanent delete (trash purge) just in case
    nuxeo_api POST "/path/default-domain/workspaces/Projects/Confidential-HR/@op/Document.Delete" '{}' > /dev/null 2>&1 || true
    echo "  Cleanup command sent."
    sleep 2
fi

# -----------------------------------------------------------------------
# Step 3: Verify prerequisites exist
# -----------------------------------------------------------------------
echo "Verifying prerequisites..."

# Check Projects workspace exists
if ! doc_exists "/default-domain/workspaces/Projects"; then
    echo "  WARNING: Projects workspace not found, creating..."
    create_doc_if_missing "/default-domain/workspaces" "Workspace" "Projects" \
        "Projects" "Active project documents and deliverables"
fi

# Check jsmith user exists
JSMITH_CHECK=$(curl -s -o /dev/null -w "%{http_code}" -u "$NUXEO_AUTH" \
    "$NUXEO_URL/api/v1/user/jsmith")
if [ "$JSMITH_CHECK" != "200" ]; then
    echo "  User jsmith not found, creating..."
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
                "email": "jsmith@example.com",
                "password": "jsmith123",
                "groups": ["members"]
            }
        }' > /dev/null
fi

# -----------------------------------------------------------------------
# Step 4: Prepare UI
# -----------------------------------------------------------------------
echo "Opening Firefox to Projects workspace..."

# Start Firefox or reload if open
open_nuxeo_url "$NUXEO_UI/#!/browse/default-domain/workspaces/Projects" 10

# Check if login is needed (if title contains 'Login')
PAGE_TITLE=$(ga_x "xdotool getactivewindow getwindowname" 2>/dev/null || echo "")
if echo "$PAGE_TITLE" | grep -qi "Login"; then
    nuxeo_login
    # After login, navigate to Projects specifically
    navigate_to "$NUXEO_UI/#!/browse/default-domain/workspaces/Projects"
fi

# Ensure window is maximized
ga_x "wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz" 2>/dev/null || true

# -----------------------------------------------------------------------
# Step 5: Capture initial state
# -----------------------------------------------------------------------
echo "Capturing initial state..."
sleep 2
ga_x "scrot /tmp/task_initial.png" 2>/dev/null || true

echo "=== Task setup complete ==="