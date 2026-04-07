#!/bin/bash
set -e
echo "=== Setting up trash_and_restore_documents task ==="

source /workspace/scripts/task_utils.sh

# 1. Record task start time
date +%s > /tmp/task_start_time.txt

# 2. Wait for Nuxeo to be fully ready
wait_for_nuxeo 120

# 3. Ensure base documents exist in Projects workspace
echo "Ensuring base documents exist..."

# Annual Report 2023 (should already be there from env setup, but ensure it)
if ! doc_exists "/default-domain/workspaces/Projects/Annual-Report-2023"; then
    echo "Creating Annual Report 2023..."
    # We'll just create a File doc with empty content if the PDF isn't handy, 
    # but the environment usually has it. We'll use the API to be safe.
    create_doc_if_missing "/default-domain/workspaces/Projects" "File" "Annual-Report-2023" "Annual Report 2023" "Financial report"
fi

# Project Proposal
if ! doc_exists "/default-domain/workspaces/Projects/Project-Proposal"; then
    create_doc_if_missing "/default-domain/workspaces/Projects" "File" "Project-Proposal" "Project Proposal" "Initial proposal"
fi

# Q3 Status Report (Note)
create_doc_if_missing "/default-domain/workspaces/Projects" "Note" "Q3-Status-Report" "Q3 Status Report" "Status update"

# Budget Forecast 2024 (Note)
create_doc_if_missing "/default-domain/workspaces/Projects" "Note" "Budget-Forecast-2024" "Budget Forecast 2024" "Financial forecast"

# 4. Create and TRASH "Meeting Minutes Q2"
echo "Setting up 'Meeting Minutes Q2' (to be trashed)..."
# First delete it if it exists to start fresh
curl -s -u "$NUXEO_AUTH" -X DELETE "$NUXEO_URL/api/v1/path/default-domain/workspaces/Projects/Meeting-Minutes-Q2" >/dev/null 2>&1 || true

# Create it
create_doc_if_missing "/default-domain/workspaces/Projects" "Note" "Meeting-Minutes-Q2" "Meeting Minutes Q2" "Critical minutes from Q2"

# Trash it using Automation API
echo "Trashing Meeting Minutes Q2..."
curl -s -u "$NUXEO_AUTH" \
    -H "Content-Type: application/json" \
    -X POST "$NUXEO_URL/api/v1/automation/Document.Trash" \
    -d '{"input":"/default-domain/workspaces/Projects/Meeting-Minutes-Q2"}' > /dev/null

# 5. Launch Firefox to the Projects workspace
echo "Launching Firefox..."
open_nuxeo_url "$NUXEO_UI/#!/browse/default-domain/workspaces/Projects" 10

# 6. Ensure window is maximized (redundant but safe)
DISPLAY=:1 wmctrl -r "Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# 7. Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="