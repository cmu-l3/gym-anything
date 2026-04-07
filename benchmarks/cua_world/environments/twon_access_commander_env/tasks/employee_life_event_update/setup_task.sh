#!/bin/bash
echo "=== Setting up task ==="
source /workspace/scripts/task_utils.sh

wait_for_ac_demo
ac_login

# Find Rachel Goldstein's ID with retry
for i in {1..5}; do
    USER_ID=$(ac_api GET "/users" | jq -r '.[] | select(.firstName=="Rachel" and .lastName=="Goldstein") | .id' 2>/dev/null)
    if [ -n "$USER_ID" ] && [ "$USER_ID" != "null" ]; then
        break
    fi
    sleep 2
done

if [ -z "$USER_ID" ] || [ "$USER_ID" == "null" ]; then
    echo "WARNING: Rachel Goldstein not found! Recreating her..."
    CREATE_RESP=$(ac_api POST "/users" '{"firstName":"Rachel","lastName":"Goldstein","email":"r.goldstein@buildingtech.com","company":"BuildingTech Solutions","enabled":true}')
    USER_ID=$(echo "$CREATE_RESP" | jq -r '.id // .userId // empty' 2>/dev/null)
fi

echo "Target User ID: $USER_ID"
echo "$USER_ID" > /tmp/target_user_id.txt

# Record task start time
date +%s > /tmp/task_start_time.txt

# Launch Firefox to the Users page
launch_firefox_to "${AC_URL}/#/users" 8

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="