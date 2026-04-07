#!/bin/bash
set -e
echo "=== Setting up Bulk Tag Distributed Documents task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# 1. Wait for Nuxeo to be ready
wait_for_nuxeo 120

# 2. Create Workspace Structure
echo "Creating workspaces..."
# Projects and Templates usually exist, but ensure DeepStorage exists
create_doc_if_missing "/default-domain/workspaces" "Workspace" "Projects" "Projects"
create_doc_if_missing "/default-domain/workspaces" "Workspace" "Templates" "Templates"
create_doc_if_missing "/default-domain/workspaces" "Workspace" "DeepStorage" "Deep Storage" "Archive location for old docs"

# 3. Create Documents via REST API
# We create them directly to ensure a known initial state
echo "Creating distributed documents..."

# Helper to create file doc
create_test_doc() {
    local parent="$1"
    local name="$2"
    local title="$3"
    local desc="$4"
    
    # Check if exists
    if doc_exists "$parent/$name"; then
        # If exists, reset tags just in case
        curl -s -u "$NUXEO_AUTH" -H "Content-Type: application/json" \
            -X PUT "$NUXEO_URL/api/v1/path$parent/$name" \
            -d '{"properties":{"nxtag:tags":[]}}' > /dev/null
        echo "Reset tags for existing $name"
    else
        # Create new
        local payload
        payload=$(cat <<EOFJSON
{
  "entity-type": "document",
  "type": "File",
  "name": "$name",
  "properties": {
    "dc:title": "$title",
    "dc:description": "$desc",
    "nxtag:tags": []
  }
}
EOFJSON
)
        nuxeo_api POST "/path$parent/" "$payload" > /dev/null
        echo "Created $name"
    fi
}

# Target 1: Projects
create_test_doc "/default-domain/workspaces/Projects" "Legacy-Policy-2020" "Legacy Policy 2020 - HR" "Old HR policy"

# Target 2: Templates
create_test_doc "/default-domain/workspaces/Templates" "Legacy-Policy-Template" "Legacy Policy Template v1" "Deprecated template"

# Target 3: DeepStorage
create_test_doc "/default-domain/workspaces/DeepStorage" "Legacy-Policy-Draft" "Legacy Policy Draft (Scanned)" "Scanned copy"

# Distractor: Projects
create_test_doc "/default-domain/workspaces/Projects" "Active-Policy-2024" "Active Policy 2024 - Remote Work" "Current active policy"

# 4. Wait for Indexing (Elasticsearch)
# Search results might not appear immediately if we don't wait a bit
echo "Waiting for indexing..."
sleep 5

# 5. Setup Browser
echo "Launching Firefox..."
# Open Nuxeo UI home
if ! pgrep -f "firefox" > /dev/null; then
    open_nuxeo_url "$NUXEO_UI" 10
else
    navigate_to "$NUXEO_UI"
fi

# Ensure logged in
sleep 5
PAGE_TITLE=$(DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority \
    xdotool getactivewindow getwindowname 2>/dev/null || echo "")
if ! echo "$PAGE_TITLE" | grep -q " - Nuxeo Platform"; then
    nuxeo_login
fi

# Take initial screenshot
echo "Capturing initial state..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="