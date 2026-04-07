#!/bin/bash
# Setup script for archive_note_as_pdf task
# Creates the source Note and ensures a clean state (no existing archive).

set -e
echo "=== Setting up archive_note_as_pdf task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Wait for Nuxeo to be ready
wait_for_nuxeo 120

# 1. Ensure Projects workspace exists
if ! doc_exists "/default-domain/workspaces/Projects"; then
    create_doc_if_missing "/default-domain/workspaces" "Workspace" "Projects" "Projects" "Project workspace"
fi

# 2. Clean up: Delete the "Archived" document if it already exists from a previous run
# We search by title/path to ensure a clean slate
echo "Cleaning up previous archived documents..."
EXISTING_ARCHIVE=$(nuxeo_api GET "/path/default-domain/workspaces/Projects/Q3-Status-Report---Archived" 2>/dev/null)
if echo "$EXISTING_ARCHIVE" | grep -q "\"uid\""; then
    UID_TO_DELETE=$(echo "$EXISTING_ARCHIVE" | python3 -c "import sys,json; print(json.load(sys.stdin).get('uid'))")
    nuxeo_api DELETE "/id/$UID_TO_DELETE" > /dev/null
    echo "Deleted existing archived document."
fi

# 3. Create the source "Q3 Status Report" Note
echo "Creating source Note..."
NOTE_PATH="/default-domain/workspaces/Projects/Q3-Status-Report"
if ! doc_exists "$NOTE_PATH"; then
    # Create the note
    # We use HTML content for the note to make it realistic
    NOTE_CONTENT="<h2>Q3 Status Report</h2><p><strong>Date:</strong> October 15, 2023</p><h3>Executive Summary</h3><p>The project is currently on track. Key milestones for Phase 1 have been met.</p><h3>Financials</h3><ul><li>Budget Utilized: 75%</li><li>Remaining: 25%</li></ul><h3>Risks</h3><p>None identified at this stage.</p>"
    
    PAYLOAD=$(cat <<EOF
{
  "entity-type": "document",
  "type": "Note",
  "name": "Q3-Status-Report",
  "properties": {
    "dc:title": "Q3 Status Report",
    "dc:description": "Live status report for Q3",
    "note:note": "$NOTE_CONTENT",
    "note:mime_type": "text/html"
  }
}
EOF
)
    nuxeo_api POST "/path/default-domain/workspaces/Projects/" "$PAYLOAD" > /dev/null
    echo "Created 'Q3 Status Report' note."
else
    echo "'Q3 Status Report' note already exists."
fi

# 4. Clear Downloads folder to prevent confusion
rm -f /home/ga/Downloads/*

# 5. Launch Firefox and login
open_nuxeo_url "$NUXEO_URL/login.jsp" 10
nuxeo_login

# 6. Navigate to the Projects workspace
navigate_to "$NUXEO_UI/#!/browse/default-domain/workspaces/Projects"

# 7. Initial Screenshot
echo "Capturing initial state..."
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="