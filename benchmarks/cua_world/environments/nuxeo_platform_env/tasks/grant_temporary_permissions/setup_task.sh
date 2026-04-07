#!/bin/bash
# Setup script for grant_temporary_permissions
set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up task: grant_temporary_permissions ==="

# 1. Wait for Nuxeo to be fully ready
wait_for_nuxeo 300

# 2. Create the target user 'contractor_sam' if not exists
echo "Creating user contractor_sam..."
if ! nuxeo_api GET "/user/contractor_sam" | grep -q "contractor_sam"; then
    USER_PAYLOAD='{"entity-type":"user","id":"contractor_sam","properties":{"username":"contractor_sam","firstName":"Sam","lastName":"Vendor","password":"password123","groups":["members"]}}'
    nuxeo_api POST "/user" "$USER_PAYLOAD" > /dev/null
    echo "User contractor_sam created."
else
    echo "User contractor_sam already exists."
fi

# 3. Create the 'VendorContracts' workspace
echo "Creating VendorContracts workspace..."
create_doc_if_missing "/default-domain/workspaces" "Workspace" "VendorContracts" "Vendor Contracts" "Workspace for vendor agreements and legal docs"

# 4. Clean any existing permissions for contractor_sam on this workspace
# (Ensures a clean start state so we don't verify old permissions)
echo "Cleaning existing permissions..."
# Nuxeo API to remove specific ACL is complex, so we'll just try to remove the 'local' ACL if it exists
# or rely on the verification checking for a *new* permission.
# Ideally, we'd use an operation, but for simplicity we rely on the anti-gaming timestamp check
# and the fact that a fresh env won't have this specific configuration.

# 5. Record task start time (CRITICAL for anti-gaming)
date +%s > /tmp/task_start_time.txt

# 6. Launch Firefox and navigate to the workspace
# We use the UI URL format
TARGET_URL="$NUXEO_UI/#!/browse/default-domain/workspaces/VendorContracts"

echo "Launching Firefox to: $TARGET_URL"
# Ensure Firefox is open and logged in
if ! pgrep -f "firefox" > /dev/null; then
    open_nuxeo_url "$NUXEO_URL/login.jsp" 10
    nuxeo_login
    navigate_to "$TARGET_URL"
else
    # If already running, just navigate
    navigate_to "$TARGET_URL"
fi

# 7. Take initial screenshot
echo "Capturing initial state..."
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="