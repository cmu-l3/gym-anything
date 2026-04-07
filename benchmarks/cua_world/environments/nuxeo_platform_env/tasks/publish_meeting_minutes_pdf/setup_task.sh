#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up task: Publish Meeting Minutes as PDF ==="

# 1. Record task start time
date +%s > /tmp/task_start_time.txt

# 2. Ensure Nuxeo is ready
wait_for_nuxeo 120

# 3. Create 'Corporate Records' workspace/folder if missing
if ! doc_exists "/default-domain/workspaces/Corporate-Records"; then
    create_doc_if_missing "/default-domain/workspaces" "Workspace" "Corporate-Records" \
        "Corporate Records" "Official repository for finalized documents"
fi

# 4. Create Source Note 'Q3 Board Minutes' in Projects
# We include a unique string for content verification (hidden in small tag)
UNIQUE_STR="Ref-Verification-7734"
NOTE_CONTENT="<h1>Q3 Board Meeting Minutes</h1><p><strong>Date:</strong> October 15, 2023</p><p><strong>Attendees:</strong> J. Doe, A. Smith, B. Jones</p><h2>Agenda</h2><ul><li>Financial Review</li><li>Strategic Planning</li><li>Executive Session</li></ul><h2>Decisions</h2><p>1. The board unanimously approved the Q3 financial report.</p><p>2. The merger proposal was tabled for Q4.</p><hr/><p><small>$UNIQUE_STR</small></p>"

# Escape quotes for JSON payload
JSON_CONTENT=$(echo "$NOTE_CONTENT" | sed 's/"/\\"/g')

if ! doc_exists "/default-domain/workspaces/Projects/Q3-Board-Minutes"; then
    echo "Creating source Note..."
    PAYLOAD=$(cat <<EOF
{
  "entity-type": "document",
  "type": "Note",
  "name": "Q3-Board-Minutes",
  "properties": {
    "dc:title": "Q3 Board Minutes",
    "dc:description": "Draft minutes for the Q3 board meeting",
    "note:note": "$JSON_CONTENT"
  }
}
EOF
)
    nuxeo_api POST "/path/default-domain/workspaces/Projects/" "$PAYLOAD" > /dev/null
    echo "Created 'Q3 Board Minutes' note."
else
    # Update content to ensure unique string is present (in case of re-run)
    echo "Updating existing Note content..."
    PAYLOAD=$(cat <<EOF
{
  "entity-type": "document",
  "properties": {
    "note:note": "$JSON_CONTENT",
    "uid:major_version": 0,
    "uid:minor_version": 1
  }
}
EOF
)
    nuxeo_api PUT "/path/default-domain/workspaces/Projects/Q3-Board-Minutes" "$PAYLOAD" > /dev/null
fi

# 5. Clean up any previous attempt (remove file from Corporate Records)
# We check for exact name match
TARGET_UID=$(curl -s -u "$NUXEO_AUTH" "$NUXEO_URL/api/v1/path/default-domain/workspaces/Corporate-Records/Q3-Board-Minutes-Final.pdf" | python3 -c "import sys,json; print(json.load(sys.stdin).get('uid',''))" 2>/dev/null || true)

if [ -n "$TARGET_UID" ]; then
    echo "Removing stale target file..."
    nuxeo_api DELETE "/id/$TARGET_UID"
fi

# 6. Clean up Downloads folder to prevent confusion
rm -f /home/ga/Downloads/*.pdf
rm -f /home/ga/*.pdf

# 7. Open Nuxeo UI and login
open_nuxeo_url "$NUXEO_UI"
nuxeo_login

# 8. Navigate user to the Projects workspace
navigate_to "http://localhost:8080/nuxeo/ui/#!/browse/default-domain/workspaces/Projects"

# 9. Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="