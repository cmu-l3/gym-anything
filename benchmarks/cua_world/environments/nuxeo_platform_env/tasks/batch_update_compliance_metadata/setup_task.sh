#!/bin/bash
# Setup for batch_update_compliance_metadata task
# Ensures documents exist and metadata fields are cleared to known initial state.

set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up batch_update_compliance_metadata task ==="

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Wait for Nuxeo to be ready
wait_for_nuxeo 120

# 1. Ensure the Projects workspace exists
if ! doc_exists "/default-domain/workspaces/Projects"; then
    create_doc_if_missing "/default-domain/workspaces" "Workspace" "Projects" \
        "Projects" "Active project documents and deliverables"
fi

# 2. Ensure target documents exist (recreate/upload if missing)
# Annual Report 2023
if ! doc_exists "/default-domain/workspaces/Projects/Annual-Report-2023"; then
    echo "Creating missing Annual Report..."
    if [ -f "/workspace/data/annual_report_2023.pdf" ]; then
        # Use simple creation if file exists, or empty file if not
        # For setup simplicity, we'll create a File doc without binary if needed, 
        # but typically the env setup handles this.
        # Here we just create the document wrapper to ensure it exists.
        PAYLOAD='{"entity-type":"document","type":"File","name":"Annual-Report-2023","properties":{"dc:title":"Annual Report 2023"}}'
        nuxeo_api POST "/path/default-domain/workspaces/Projects/" "$PAYLOAD" > /dev/null
    fi
fi

# Project Proposal
if ! doc_exists "/default-domain/workspaces/Projects/Project-Proposal"; then
    echo "Creating missing Project Proposal..."
    PAYLOAD='{"entity-type":"document","type":"File","name":"Project-Proposal","properties":{"dc:title":"Project Proposal"}}'
    nuxeo_api POST "/path/default-domain/workspaces/Projects/" "$PAYLOAD" > /dev/null
fi

# Q3 Status Report
if ! doc_exists "/default-domain/workspaces/Projects/Q3-Status-Report"; then
    echo "Creating missing Q3 Status Report..."
    PAYLOAD='{"entity-type":"document","type":"Note","name":"Q3-Status-Report","properties":{"dc:title":"Q3 Status Report","note:note":"<p>Status report content.</p>"}}'
    nuxeo_api POST "/path/default-domain/workspaces/Projects/" "$PAYLOAD" > /dev/null
fi

# 3. Clear target metadata fields to ensure clean state
# This forces the agent to actually do the work
echo "Clearing compliance metadata fields..."
docs=(
    "/default-domain/workspaces/Projects/Annual-Report-2023"
    "/default-domain/workspaces/Projects/Project-Proposal"
    "/default-domain/workspaces/Projects/Q3-Status-Report"
)

for doc_path in "${docs[@]}"; do
    # Reset specific fields to empty string
    CLEAR_PAYLOAD='{"entity-type":"document","properties":{"dc:source":"","dc:rights":"","dc:coverage":"","dc:format":""}}'
    nuxeo_api PUT "/path$doc_path" "$CLEAR_PAYLOAD" > /dev/null 2>&1
    echo "  Cleared metadata on: $doc_path"
done

sleep 2

# 4. Open Firefox to the Projects workspace
open_nuxeo_url "$NUXEO_URL/login.jsp" 8

# Login if needed (check window title)
sleep 2
PAGE_TITLE=$(DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority \
    xdotool getactivewindow getwindowname 2>/dev/null || echo "")
if ! echo "$PAGE_TITLE" | grep -q " - Nuxeo Platform"; then
    nuxeo_login
fi

# Navigate to Projects workspace
navigate_to "$NUXEO_UI/#!/browse/default-domain/workspaces/Projects"
sleep 2

# Take initial state screenshot
DISPLAY=:1 scrot /tmp/task_initial_state.png 2>/dev/null || true

echo "=== Task setup complete ==="