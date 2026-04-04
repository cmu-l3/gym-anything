#!/bin/bash
# pre_task hook for create_workspace task.
# Ensures the 'Marketing Materials' workspace does NOT exist (clean start state),
# then opens Firefox to the Workspaces listing so the agent can create it.

echo "=== Setting up create_workspace task ==="

source /workspace/scripts/task_utils.sh

wait_for_nuxeo 120

# Delete 'Marketing Materials' workspace if it exists (reset to clean state)
WS_CODE=$(curl -s -o /dev/null -w "%{http_code}" -u "$NUXEO_AUTH" \
    "$NUXEO_URL/api/v1/path/default-domain/workspaces/Marketing-Materials")
if [ "$WS_CODE" = "200" ]; then
    echo "Deleting existing 'Marketing Materials' workspace..."
    curl -s -u "$NUXEO_AUTH" \
        -X DELETE "$NUXEO_URL/api/v1/path/default-domain/workspaces/Marketing-Materials" || true
    sleep 3
fi

sleep 2

# Open Firefox to login page, log in, then navigate to Workspaces
open_nuxeo_url "$NUXEO_URL/login.jsp" 8

sleep 3
PAGE_TITLE=$(DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority \
    xdotool getactivewindow getwindowname 2>/dev/null || echo "")
if ! echo "$PAGE_TITLE" | grep -q " - Nuxeo Platform"; then
    nuxeo_login
fi

sleep 2
navigate_to "$NUXEO_UI/#!/browse/default-domain/workspaces"
sleep 4

echo "Task start state: Firefox is on the Nuxeo Workspaces listing page."
echo "Agent must create a new workspace named 'Marketing Materials'."
echo "=== create_workspace task setup complete ==="
