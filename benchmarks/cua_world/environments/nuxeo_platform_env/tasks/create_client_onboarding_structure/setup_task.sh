#!/bin/bash
set -e
echo "=== Setting up create_client_onboarding_structure task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming (folders must be created AFTER this)
date +%s > /tmp/task_start_time.txt
# ISO format for comparison with Nuxeo's dc:created (approximate)
date -u +"%Y-%m-%dT%H:%M:%S" > /tmp/task_start_iso.txt

# Wait for Nuxeo to be responsive
wait_for_nuxeo 180

# Ensure the Projects workspace exists
if ! doc_exists "/default-domain/workspaces/Projects"; then
    echo "Creating Projects workspace..."
    create_doc_if_missing "/default-domain/workspaces" "Workspace" "Projects" "Projects" "Active project documents"
fi

# Clean State: Ensure 'Meridian-Holdings' does NOT exist
# We use curl directly to check and delete
echo "Checking for existing Meridian-Holdings folder..."
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -u "$NUXEO_AUTH" \
    "$NUXEO_URL/api/v1/path/default-domain/workspaces/Projects/Meridian-Holdings")

if [ "$HTTP_CODE" = "200" ]; then
    echo "Removing existing Meridian-Holdings folder to ensure clean state..."
    curl -s -u "$NUXEO_AUTH" -X DELETE \
        "$NUXEO_URL/api/v1/path/default-domain/workspaces/Projects/Meridian-Holdings" || true
    sleep 2
fi

# Clean up any previous summary file
rm -f /home/ga/onboarding_summary.json

# Prepare the browser
# We open Firefox and navigate to the Projects folder so the agent is ready to work
echo "Launching Firefox..."
open_nuxeo_url "$NUXEO_URL/login.jsp" 10

# Check if we need to login
if ! ga_x "xdotool getwindowname \$(xdotool getactivewindow)" | grep -q "Nuxeo"; then
    nuxeo_login
fi

# Navigate to Projects workspace
navigate_to "$NUXEO_UI/#!/browse/default-domain/workspaces/Projects"

# Capture initial screenshot
echo "Capturing initial state..."
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="