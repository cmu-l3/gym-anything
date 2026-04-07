#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up task: cleanup_obsolete_drafts ==="

# Record start time
date +%s > /tmp/task_start_time.txt

# Ensure Nuxeo is ready
wait_for_nuxeo 180

# Clean up previous run if exists
if doc_exists "/default-domain/workspaces/Cleanup_Zone"; then
    echo "Removing existing Cleanup_Zone..."
    curl -s -u "$NUXEO_AUTH" -X DELETE "$NUXEO_URL/api/v1/path/default-domain/workspaces/Cleanup_Zone" > /dev/null
    sleep 2
fi

# Create Cleanup_Zone workspace
echo "Creating Cleanup_Zone workspace..."
create_doc_if_missing "/default-domain/workspaces" "Workspace" "Cleanup_Zone" \
    "Cleanup Zone" "Area for document review and maintenance"

# Helper to create note documents
create_cleanup_doc() {
    local name="$1"
    local title="$2"
    local desc="$3"
    
    local payload
    payload=$(cat <<EOFJSON
{
  "entity-type": "document",
  "type": "Note",
  "name": "$name",
  "properties": {
    "dc:title": "$title",
    "dc:description": "$desc",
    "note:note": "<p>Content for $title</p>",
    "note:mime_type": "text/html"
  }
}
EOFJSON
)
    nuxeo_api POST "/path/default-domain/workspaces/Cleanup_Zone/" "$payload" > /dev/null
    echo "Created document: $name"
}

# 1. Obsolete Draft v1 (Target: TRASH)
create_cleanup_doc "Project-Alpha-Draft-v1" "Project Alpha - Draft v1" \
    "Obsolete initial draft from 2022 - ARCHIVE ONLY"

# 2. Obsolete Draft v2 (Target: TRASH)
create_cleanup_doc "Project-Alpha-Draft-v2" "Project Alpha - Draft v2" \
    "Obsolete review copy, superseded by Final version"

# 3. Final (Target: KEEP)
create_cleanup_doc "Project-Alpha-Final" "Project Alpha - Final" \
    "Approved and signed 2023 version"

# 4. Active Draft (Target: KEEP) - Tricky: Title says Draft, Desc says Active
create_cleanup_doc "Project-Beta-Draft" "Project Beta - Draft" \
    "Active working copy - DO NOT DELETE"

# 5. Reference (Target: KEEP)
create_cleanup_doc "Regulatory-Reference" "Regulatory Reference" \
    "Permanent record for audit compliance"

sleep 2

# Launch Firefox to the workspace
echo "Launching Firefox..."
open_nuxeo_url "$NUXEO_UI/#!/browse/default-domain/workspaces/Cleanup_Zone" 8

# Ensure login if needed (open_nuxeo_url might land on login if session expired)
# Check window title
sleep 5
PAGE_TITLE=$(ga_x "xdotool getactivewindow getwindowname" 2>/dev/null || echo "")
if echo "$PAGE_TITLE" | grep -q "Login"; then
    nuxeo_login
fi

# Take initial screenshot
echo "Capturing initial state..."
sleep 2
ga_x "scrot /tmp/task_initial.png" 2>/dev/null || true

echo "=== Task setup complete ==="