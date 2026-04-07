#!/bin/bash
set -e
echo "=== Setting up Release Specific User Locks task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Wait for Nuxeo to be fully ready
wait_for_nuxeo 120

# 1. Ensure 'Projects' workspace exists
echo "Ensuring Projects workspace exists..."
if ! doc_exists "/default-domain/workspaces/Projects"; then
    create_doc_if_missing "/default-domain/workspaces" "Workspace" "Projects" "Projects" "Project files"
fi

# 2. Ensure target documents exist
echo "Ensuring documents exist..."
# Annual Report
if ! doc_exists "/default-domain/workspaces/Projects/Annual-Report-2023"; then
    create_doc_if_missing "/default-domain/workspaces/Projects" "File" "Annual-Report-2023" "Annual Report 2023" "Financial Report"
fi
# Project Proposal
if ! doc_exists "/default-domain/workspaces/Projects/Project-Proposal"; then
    create_doc_if_missing "/default-domain/workspaces/Projects" "File" "Project-Proposal" "Project Proposal" "Draft proposal"
fi
# Q3 Status Report
if ! doc_exists "/default-domain/workspaces/Projects/Q3-Status-Report"; then
    create_doc_if_missing "/default-domain/workspaces/Projects" "Note" "Q3-Status-Report" "Q3 Status Report" "Status update"
fi

# 3. Ensure user 'jsmith' exists (usually created by base setup, but verify)
echo "Verifying user jsmith..."
USER_CODE=$(curl -s -o /dev/null -w "%{http_code}" -u "$NUXEO_AUTH" "$NUXEO_URL/api/v1/user/jsmith")
if [ "$USER_CODE" != "200" ]; then
    echo "Creating user jsmith..."
    curl -s -u "$NUXEO_AUTH" -H "Content-Type: application/json" \
        -X POST "$NUXEO_URL/api/v1/user/" \
        -d '{"entity-type":"user","id":"jsmith","properties":{"username":"jsmith","password":"jsmith123","firstName":"John","lastName":"Smith","groups":["members"]}}' > /dev/null
fi

# 4. Apply Locks
echo "Applying initial locks..."

# Helper to lock a document
lock_document() {
    local path="$1"
    local user="$2"
    local pass="$3"
    
    # Get UID
    local uid
    uid=$(nuxeo_api GET "/path/default-domain/workspaces/Projects/$path" | python3 -c "import sys,json; print(json.load(sys.stdin).get('uid',''))")
    
    if [ -n "$uid" ]; then
        # Check if already locked
        local current_lock
        current_lock=$(curl -s -u "$NUXEO_AUTH" "$NUXEO_URL/api/v1/id/$uid" | python3 -c "import sys,json; print(json.load(sys.stdin).get('lockOwner',''))")
        
        if [ "$current_lock" != "$user" ]; then
            # If locked by someone else, unlock first (as admin)
            if [ -n "$current_lock" ]; then
                curl -s -u "$NUXEO_AUTH" -X DELETE "$NUXEO_URL/api/v1/id/$uid/@op/Document.RemoveLock" > /dev/null
            fi
            # Lock as target user
            curl -s -u "$user:$pass" -H "Content-Type: application/json" \
                -X POST "$NUXEO_URL/api/v1/id/$uid/@op/Document.Lock" > /dev/null
            echo "  Locked $path as $user"
        else
            echo "  $path already locked by $user"
        fi
    fi
}

lock_document "Annual-Report-2023" "jsmith" "jsmith123"
lock_document "Project-Proposal" "jsmith" "jsmith123"
lock_document "Q3-Status-Report" "Administrator" "Administrator"

# 5. Launch Browser
echo "Launching Firefox..."
open_nuxeo_url "$NUXEO_URL/login.jsp" 8

# Automate login
PAGE_TITLE=$(DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority \
    xdotool getactivewindow getwindowname 2>/dev/null || echo "")
if ! echo "$PAGE_TITLE" | grep -q " - Nuxeo Platform"; then
    nuxeo_login
fi

# Navigate to Projects workspace
sleep 2
navigate_to "$NUXEO_UI/#!/browse/default-domain/workspaces/Projects"
sleep 3

# 6. Capture Initial State
echo "Capturing initial state..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="