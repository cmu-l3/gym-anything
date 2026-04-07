#!/bin/bash
echo "=== Setting up enroll_license_plates_lpr task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Wait for 2N Access Commander inner VM to become reachable
wait_for_ac_demo
ac_login

# Ensure clean slate for license plates if the task was restarted
# (This queries the API to ensure neither target user accidentally has plates assigned initially)
KWAME_ID=$(ac_api GET "/users" | jq -r '.[] | select(.firstName=="Kwame" and .lastName=="Asante") | .id' 2>/dev/null || echo "")
if [ -n "$KWAME_ID" ] && [ "$KWAME_ID" != "null" ]; then
    # The API might vary slightly, but we can patch the user record to empty carLicensePlates
    ac_api PUT "/users/$KWAME_ID" '{"carLicensePlates":[]}' > /dev/null 2>&1 || true
fi

MEI_ID=$(ac_api GET "/users" | jq -r '.[] | select(.firstName=="Mei-Ling" and .lastName=="Zhang") | .id' 2>/dev/null || echo "")
if [ -n "$MEI_ID" ] && [ "$MEI_ID" != "null" ]; then
    ac_api PUT "/users/$MEI_ID" '{"carLicensePlates":[]}' > /dev/null 2>&1 || true
fi

# Launch Firefox directly to the Users page
launch_firefox_to "${AC_URL}/#/users" 8

# Take initial screenshot for evidence
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="