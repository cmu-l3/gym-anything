#!/bin/bash
# pre_task hook for create_user task.
# Deletes user 'mwilson' if it already exists (clean state),
# then opens Firefox to the Users & Groups admin page.

echo "=== Setting up create_user task ==="

source /workspace/scripts/task_utils.sh

wait_for_nuxeo 120

# Delete user mwilson if exists
USER_CODE=$(curl -s -o /dev/null -w "%{http_code}" -u "$NUXEO_AUTH" \
    "$NUXEO_URL/api/v1/user/mwilson")
if [ "$USER_CODE" = "200" ]; then
    curl -s -u "$NUXEO_AUTH" -X DELETE "$NUXEO_URL/api/v1/user/mwilson" > /dev/null
    echo "Deleted existing user mwilson."
fi

sleep 2

# Open Firefox, log in, navigate to Users & Groups admin page
open_nuxeo_url "$NUXEO_URL/login.jsp" 8

sleep 3
PAGE_TITLE=$(DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority \
    xdotool getactivewindow getwindowname 2>/dev/null || echo "")
if ! echo "$PAGE_TITLE" | grep -q " - Nuxeo Platform"; then
    nuxeo_login
fi

sleep 2
navigate_to "$NUXEO_UI/#!/admin/user-group-management"
sleep 4

echo "Task start state: Firefox is on the Users & Groups management page."
echo "Agent must create user: mwilson / Margaret Wilson / mwilson@acme.com"
echo "=== create_user task setup complete ==="
