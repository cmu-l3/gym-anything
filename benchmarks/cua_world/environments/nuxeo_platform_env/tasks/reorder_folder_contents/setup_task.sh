#!/bin/bash
set -e
echo "=== Setting up Reorder Folder Contents task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

wait_for_nuxeo 120

# 1. Ensure Projects workspace exists
if ! doc_exists "/default-domain/workspaces/Projects"; then
    create_doc_if_missing "/default-domain/workspaces" "Workspace" "Projects" "Projects"
fi

# 2. Create the OrderedFolder 'Onboarding-Checklist'
# We use type "OrderedFolder" specifically to enable manual ordering
FOLDER_PATH="/default-domain/workspaces/Projects/Onboarding-Checklist"
if doc_exists "$FOLDER_PATH"; then
    # Delete existing to ensure clean state and correct initial order (which is wrong)
    curl -s -u "$NUXEO_AUTH" -X DELETE "$NUXEO_URL/api/v1/path$FOLDER_PATH" > /dev/null
    sleep 2
fi

echo "Creating OrderedFolder 'Onboarding-Checklist'..."
PAYLOAD='{
  "entity-type": "document",
  "type": "OrderedFolder",
  "name": "Onboarding-Checklist",
  "properties": {
    "dc:title": "Onboarding Checklist",
    "dc:description": "HR onboarding steps for new employees"
  }
}'
nuxeo_api POST "/path/default-domain/workspaces/Projects/" "$PAYLOAD" > /dev/null

# 3. Create children in the WRONG order: Step 3, Step 1, Step 2
# Nuxeo appends new children to the end of the list in OrderedFolders
echo "Creating documents in mixed order..."

# Helper to create note
create_step() {
    local name="$1"
    local title="$2"
    PAYLOAD=$(cat <<EOF
{
  "entity-type": "document",
  "type": "Note",
  "name": "$name",
  "properties": {
    "dc:title": "$title",
    "note:note": "<h3>$title</h3><p>Content for $title...</p>"
  }
}
EOF
)
    nuxeo_api POST "/path$FOLDER_PATH/" "$PAYLOAD" > /dev/null
    echo "  Created $title"
}

create_step "Step-3" "Step 3: Assessment"
sleep 1
create_step "Step-1" "Step 1: Preparation"
sleep 1
create_step "Step-2" "Step 2: Training"

# Record initial order for debugging
curl -s -u "$NUXEO_AUTH" "$NUXEO_URL/api/v1/path$FOLDER_PATH/@children" > /tmp/initial_order.json

# 4. Open Firefox to the folder
echo "Opening browser..."
open_nuxeo_url "$NUXEO_UI/#!/browse$FOLDER_PATH" 8

# 5. Login
nuxeo_login

# Take initial screenshot
echo "Capturing initial state..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="