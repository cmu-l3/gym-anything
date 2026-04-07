#!/bin/bash
# Pre-task setup for reassign_workflow_task
# 1. Creates users jsmith and jdoe
# 2. Ensures Annual Report 2023 exists
# 3. Starts a Parallel Document Review workflow assigned to jsmith
# 4. Records initial state for anti-gaming

echo "=== Setting up reassign_workflow_task task ==="

source /workspace/scripts/task_utils.sh

# Wait for Nuxeo to be responsive
wait_for_nuxeo 180

# ---------------------------------------------------------------------------
# 1. Create Users
# ---------------------------------------------------------------------------
echo "Creating/Verifying users..."

# Create jsmith
if ! nuxeo_api GET "/user/jsmith" | grep -q "jsmith"; then
    echo "Creating user jsmith..."
    nuxeo_api POST "/user" '{
        "entity-type": "user",
        "id": "jsmith",
        "properties": {
            "username": "jsmith",
            "firstName": "John",
            "lastName": "Smith",
            "email": "jsmith@example.com",
            "password": "password123",
            "groups": ["members"]
        }
    }' > /dev/null
fi

# Create jdoe
if ! nuxeo_api GET "/user/jdoe" | grep -q "jdoe"; then
    echo "Creating user jdoe..."
    nuxeo_api POST "/user" '{
        "entity-type": "user",
        "id": "jdoe",
        "properties": {
            "username": "jdoe",
            "firstName": "Jane",
            "lastName": "Doe",
            "email": "jdoe@example.com",
            "password": "jdoe123",
            "groups": ["members"]
        }
    }' > /dev/null
fi

# ---------------------------------------------------------------------------
# 2. Prepare Document
# ---------------------------------------------------------------------------
echo "Preparing document..."
DOC_PATH="/default-domain/workspaces/Projects/Annual-Report-2023"

# Ensure Projects workspace exists
if ! doc_exists "/default-domain/workspaces/Projects"; then
    create_doc_if_missing "/default-domain/workspaces" "Workspace" "Projects" "Projects"
fi

# Ensure Annual Report exists
if ! doc_exists "$DOC_PATH"; then
    # Create it if missing (simple File doc)
    create_doc_if_missing "/default-domain/workspaces/Projects" "File" "Annual-Report-2023" "Annual Report 2023" "Financial Report"
fi

# Get Document ID
DOC_ID=$(nuxeo_api GET "/path$DOC_PATH" | python3 -c "import sys,json; print(json.load(sys.stdin).get('uid',''))")
echo "Document UID: $DOC_ID"

# ---------------------------------------------------------------------------
# 3. Setup Workflow
# ---------------------------------------------------------------------------
echo "Setting up workflow..."

# Cancel ANY existing workflows on this document to ensure clean state
WORKFLOWS=$(nuxeo_api GET "/id/$DOC_ID/@workflow")
echo "$WORKFLOWS" | python3 -c "
import sys, json
data = json.load(sys.stdin)
for wf in data.get('entries', []):
    print(wf.get('id'))
" | while read -r WF_ID; do
    if [ -n "$WF_ID" ]; then
        echo "Cancelling existing workflow $WF_ID..."
        nuxeo_api DELETE "/workflow/$WF_ID" > /dev/null
    fi
done

# Start new Parallel Document Review workflow assigned to jsmith
# Note: The API payload structure for starting workflow depends on the model
# Using standard 'ParallelDocumentReview' model
echo "Starting Parallel Document Review assigned to jsmith..."
START_PAYLOAD=$(cat <<EOF
{
  "entity-type": "workflow",
  "workflowModelName": "ParallelDocumentReview",
  "attachedDocumentIds": ["$DOC_ID"],
  "variables": {
    "participants": ["user:jsmith"],
    "end_date": "2026-12-31",
    "comment": "Please review ASAP."
  }
}
EOF
)
nuxeo_api POST "/workflow" "$START_PAYLOAD" > /dev/null

sleep 3

# Verify task was created
TASKS=$(nuxeo_api GET "/task?userId=jsmith&workflowModelName=ParallelDocumentReview")
TASK_ID=$(echo "$TASKS" | python3 -c "import sys,json; entries=json.load(sys.stdin).get('entries',[]); print(entries[0]['id'] if entries else '')")

if [ -z "$TASK_ID" ]; then
    echo "ERROR: Failed to create workflow task for jsmith."
    # Retry once
    sleep 5
    TASKS=$(nuxeo_api GET "/task?userId=jsmith&workflowModelName=ParallelDocumentReview")
    TASK_ID=$(echo "$TASKS" | python3 -c "import sys,json; entries=json.load(sys.stdin).get('entries',[]); print(entries[0]['id'] if entries else '')")
fi

echo "Created Task ID: $TASK_ID"

# ---------------------------------------------------------------------------
# 4. Record Initial State
# ---------------------------------------------------------------------------
date +%s > /tmp/task_start_time.txt

cat > /tmp/initial_state.json <<EOF
{
  "doc_id": "$DOC_ID",
  "task_id": "$TASK_ID",
  "initial_actors": ["jsmith"],
  "target_user": "jdoe"
}
EOF

# ---------------------------------------------------------------------------
# 5. Launch Browser
# ---------------------------------------------------------------------------
# Open Firefox to the Task Dashboard or Document View
# Nuxeo Web UI Home: http://localhost:8080/nuxeo/ui/
echo "Launching Firefox..."
open_nuxeo_url "$NUXEO_UI/#!/browse$DOC_PATH" 8

# Automate login
nuxeo_login

# Ensure window is maximized
DISPLAY=:1 wmctrl -r "Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Initial screenshot
echo "Capturing initial state..."
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="