#!/bin/bash
set -e

echo "=== Setting up instantiate_project_from_template task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Wait for Nuxeo to be ready
wait_for_nuxeo 120

# ---------------------------------------------------------------------------
# 1. Prepare Source Template
# ---------------------------------------------------------------------------
echo "Ensuring template structure exists..."

# Create 'Templates' workspace container if missing
create_doc_if_missing "/default-domain/workspaces" "Workspace" "Templates" \
    "Templates" "Container for project templates" > /dev/null

# Create 'Standard-Project-Template' workspace
create_doc_if_missing "/default-domain/workspaces/Templates" "Workspace" "Standard-Project-Template" \
    "Standard Project Template" "Standard structure for new client projects" > /dev/null

# Create subfolders inside the template
TEMPLATE_PATH="/default-domain/workspaces/Templates/Standard-Project-Template"
create_doc_if_missing "$TEMPLATE_PATH" "Folder" "01-Planning" "01 Planning" "" > /dev/null
create_doc_if_missing "$TEMPLATE_PATH" "Folder" "02-Financials" "02 Financials" "" > /dev/null
create_doc_if_missing "$TEMPLATE_PATH" "Folder" "03-Legal" "03 Legal" "" > /dev/null

# Create a dummy checklist file in Planning
if ! doc_exists "$TEMPLATE_PATH/01-Planning/Project-Checklist"; then
    echo "Creating Project Checklist file..."
    # Upload a dummy PDF if real one not handy, or use API to create Note/File
    # Using Note for simplicity/reliability in setup
    PAYLOAD='{"entity-type":"document","type":"Note","name":"Project-Checklist","properties":{"dc:title":"Project Checklist","note:note":"<p>1. Kickoff<br>2. Budget<br>3. Sign-off</p>"}}'
    nuxeo_api POST "/path$TEMPLATE_PATH/01-Planning/" "$PAYLOAD" > /dev/null
fi

echo "Template structure verified."

# ---------------------------------------------------------------------------
# 2. Clean Destination (Ensure no stale 'Project Phoenix')
# ---------------------------------------------------------------------------
echo "Cleaning destination..."

# Delete Project-Phoenix if it exists
TARGET_PATH="/default-domain/workspaces/Projects/Project-Phoenix"
if doc_exists "$TARGET_PATH"; then
    echo "Removing stale Project-Phoenix..."
    curl -s -u "$NUXEO_AUTH" -X DELETE "$NUXEO_URL/api/v1/path$TARGET_PATH" > /dev/null
fi

# Also check for "Standard-Project-Template-copy" artifacts from failed previous runs
# This helps keep the Projects workspace clean
nuxeo_api GET "/path/default-domain/workspaces/Projects/@children" | \
python3 -c "import sys, json; 
data=json.load(sys.stdin); 
ids=[e['uid'] for e in data.get('entries',[]) if 'Standard-Project-Template' in e.get('title','')];
print(' '.join(ids))" | while read -r uid; do
    if [ -n "$uid" ]; then
        echo "Cleaning up copy artifact: $uid"
        curl -s -u "$NUXEO_AUTH" -X DELETE "$NUXEO_URL/api/v1/id/$uid" > /dev/null
    fi
done

# ---------------------------------------------------------------------------
# 3. Prepare Environment
# ---------------------------------------------------------------------------

# Maximize Firefox and ensure it's running
if ! pgrep -f firefox > /dev/null; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox &"
    sleep 5
fi

# Log in
open_nuxeo_url "$NUXEO_URL/login.jsp" 10
nuxeo_login

# Navigate to the Templates workspace (Source)
navigate_to "$NUXEO_UI/#!/browse/default-domain/workspaces/Templates"

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="