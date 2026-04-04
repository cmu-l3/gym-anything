#!/bin/bash
# pre_task hook for grant_permissions task.
# Removes any existing explicit ACL for jsmith on Projects workspace,
# then opens Firefox to the Projects workspace.

echo "=== Setting up grant_permissions task ==="

source /workspace/scripts/task_utils.sh

wait_for_nuxeo 120

# Ensure jsmith user exists
USER_CODE=$(curl -s -o /dev/null -w "%{http_code}" -u "$NUXEO_AUTH" \
    "$NUXEO_URL/api/v1/user/jsmith")
if [ "$USER_CODE" != "200" ]; then
    echo "Creating jsmith user..."
    curl -s -u "$NUXEO_AUTH" -H "Content-Type: application/json" \
        -X POST "$NUXEO_URL/api/v1/user/" \
        -d '{"entity-type":"user","id":"jsmith","properties":{"username":"jsmith","firstName":"John","lastName":"Smith","email":"jsmith@acme.com","password":"password123","groups":["members"]}}' > /dev/null
fi

# Remove jsmith from Projects workspace ACL (reset to clean state)
curl -s -u "$NUXEO_AUTH" -H "Content-Type: application/json" \
    -X POST "$NUXEO_URL/api/v1/path/default-domain/workspaces/Projects/@op/Document.RemoveACL" \
    -d '{"params":{"acl":"local"}}' > /dev/null 2>&1 || true

sleep 2

# Open Firefox, log in, navigate to Projects workspace
open_nuxeo_url "$NUXEO_URL/login.jsp" 8

sleep 3
PAGE_TITLE=$(DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority \
    xdotool getactivewindow getwindowname 2>/dev/null || echo "")
if ! echo "$PAGE_TITLE" | grep -q " - Nuxeo Platform"; then
    nuxeo_login
fi

sleep 2
navigate_to "$NUXEO_UI/#!/browse/default-domain/workspaces/Projects"
sleep 4

echo "Task start state: Firefox is on the Projects workspace."
echo "Agent must navigate to the Permissions tab and grant 'jsmith' Read access."
echo "=== grant_permissions task setup complete ==="
