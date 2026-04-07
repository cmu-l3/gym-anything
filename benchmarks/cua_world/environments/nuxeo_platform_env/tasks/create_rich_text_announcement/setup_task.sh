#!/bin/bash
# setup_task.sh for create_rich_text_announcement
set -e

echo "=== Setting up create_rich_text_announcement task ==="

source /workspace/scripts/task_utils.sh

# 1. Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# 2. Wait for Nuxeo to be responsive
wait_for_nuxeo 180

# 3. Ensure Clean State: Delete the document if it already exists
# We check for likely URL path segments
TARGET_PATH="/default-domain/workspaces/Projects/Weekend-Maintenance-Alert"
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -u "$NUXEO_AUTH" "$NUXEO_URL/api/v1/path$TARGET_PATH")

if [ "$HTTP_CODE" = "200" ]; then
    echo "Cleaning up existing document..."
    curl -s -u "$NUXEO_AUTH" -X DELETE "$NUXEO_URL/api/v1/path$TARGET_PATH" > /dev/null
    sleep 2
fi

# 4. Ensure Projects workspace exists
if ! doc_exists "/default-domain/workspaces/Projects"; then
    create_doc "/default-domain/workspaces" "Workspace" "Projects" "Projects" "Workspace for projects" > /dev/null
fi

# 5. Launch Firefox and Login
# Kill any existing Firefox to ensure clean session
pkill -f firefox 2>/dev/null || true
sleep 1

# Launch Firefox (minimized or background initially, but open_nuxeo_url handles maximizing)
# We will open directly to login page
open_nuxeo_url "$NUXEO_URL/login.jsp" 10

# Perform login automation
nuxeo_login

# Navigate to the Projects workspace
navigate_to "$NUXEO_UI/#!/browse$TARGET_PATH/.." # Navigate to parent of target (Projects)

# 6. Capture Initial State Screenshot
echo "Capturing initial state..."
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="