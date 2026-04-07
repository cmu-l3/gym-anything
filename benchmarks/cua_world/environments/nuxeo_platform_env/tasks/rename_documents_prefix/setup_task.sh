#!/bin/bash
# Setup script for rename_documents_prefix task
# Ensures Nuxeo is running, documents exist with ORIGINAL titles,
# and Firefox is open with the agent logged in.

set -e
echo "=== Setting up rename_documents_prefix task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# Wait for Nuxeo to be available
wait_for_nuxeo 120

# ---------------------------------------------------------------------------
# Ensure documents exist and have ORIGINAL titles (reset if needed)
# ---------------------------------------------------------------------------

reset_doc_title() {
    local path="$1"
    local original_title="$2"
    local type="$3"

    # Check if doc exists
    local response
    response=$(nuxeo_api GET "/path$path")
    local uid
    uid=$(echo "$response" | python3 -c "import sys,json; print(json.load(sys.stdin).get('uid',''))" 2>/dev/null)

    if [ -n "$uid" ]; then
        # Document exists, update title to original
        echo "Resetting title for $path to '$original_title'"
        nuxeo_api PUT "/path$path" "{\"entity-type\":\"document\",\"properties\":{\"dc:title\":\"$original_title\"}}" > /dev/null
    else
        # Document missing, create it
        echo "Creating missing document $path"
        local parent=$(dirname "$path")
        local name=$(basename "$path")
        
        # Determine payload based on type
        local props="{\"dc:title\":\"$original_title\"}"
        if [ "$type" = "Note" ]; then
            props="{\"dc:title\":\"$original_title\",\"note:note\":\"<p>Content for $original_title</p>\"}"
        fi
        
        nuxeo_api POST "/path$parent/" "{\"entity-type\":\"document\",\"type\":\"$type\",\"name\":\"$name\",\"properties\":$props}" > /dev/null
    fi
}

echo "Preparing documents in Projects workspace..."

# Ensure parent workspace exists
create_doc_if_missing "/default-domain/workspaces" "Workspace" "Projects" "Projects" "Project workspace" > /dev/null

# Reset/Create the 3 target documents
reset_doc_title "/default-domain/workspaces/Projects/Annual-Report-2023" "Annual Report 2023" "File"
reset_doc_title "/default-domain/workspaces/Projects/Project-Proposal" "Project Proposal" "File"
reset_doc_title "/default-domain/workspaces/Projects/Q3-Status-Report" "Q3 Status Report" "Note"

# ---------------------------------------------------------------------------
# Setup Browser
# ---------------------------------------------------------------------------

# Open Firefox with Nuxeo Web UI on the Projects workspace
open_nuxeo_url "$NUXEO_UI/#!/browse/default-domain/workspaces/Projects" 8

# Log in
nuxeo_login

# Ensure we are strictly on the Projects workspace
navigate_to "$NUXEO_UI/#!/browse/default-domain/workspaces/Projects"

# Take initial state screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="