#!/bin/bash
# Setup script for Measles Outbreak Alert Configuration task

echo "=== Setting up Measles Outbreak Alert Task ==="

source /workspace/scripts/task_utils.sh

# Inline fallback for API calls if utils fail
if ! type dhis2_api &>/dev/null; then
    dhis2_api() {
        curl -s -u admin:district "http://localhost:8080/api/$1"
    }
fi

# Verify DHIS2 is running
echo "Checking DHIS2 health..."
for i in $(seq 1 12); do
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:8080/api/system/info" 2>/dev/null)
    if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "401" ]; then
        echo "DHIS2 is responsive (HTTP $HTTP_CODE)"
        break
    fi
    echo "Waiting for DHIS2... ($i/12)"
    sleep 5
done

# Record task start time
date +%s > /tmp/task_start_timestamp
date -Iseconds > /tmp/task_start_iso
TASK_START=$(cat /tmp/task_start_iso)
echo "Task start time: $TASK_START"

# CLEANUP: Remove objects if they exist from previous runs to ensure clean state
echo "Cleaning up any existing task objects..."

# 1. Delete Notification Template
NOTIF_ID=$(dhis2_api "validationNotificationTemplates?filter=name:ilike:Measles&fields=id" | jq -r '.validationNotificationTemplates[0].id // empty')
if [ -n "$NOTIF_ID" ]; then
    echo "Deleting existing notification: $NOTIF_ID"
    curl -s -u admin:district -X DELETE "http://localhost:8080/api/validationNotificationTemplates/$NOTIF_ID"
fi

# 2. Delete Validation Rule Group
GROUP_ID=$(dhis2_api "validationRuleGroups?filter=name:ilike:Epidemic&fields=id" | jq -r '.validationRuleGroups[0].id // empty')
if [ -n "$GROUP_ID" ]; then
    echo "Deleting existing rule group: $GROUP_ID"
    curl -s -u admin:district -X DELETE "http://localhost:8080/api/validationRuleGroups/$GROUP_ID"
fi

# 3. Delete Validation Rule
RULE_ID=$(dhis2_api "validationRules?filter=name:ilike:Measles&fields=id" | jq -r '.validationRules[0].id // empty')
if [ -n "$RULE_ID" ]; then
    echo "Deleting existing rule: $RULE_ID"
    curl -s -u admin:district -X DELETE "http://localhost:8080/api/validationRules/$RULE_ID"
fi

# 4. Delete User Group
UG_ID=$(dhis2_api "userGroups?filter=name:ilike:Emergency&fields=id" | jq -r '.userGroups[0].id // empty')
if [ -n "$UG_ID" ]; then
    echo "Deleting existing user group: $UG_ID"
    curl -s -u admin:district -X DELETE "http://localhost:8080/api/userGroups/$UG_ID"
fi

# Ensure Firefox is running
echo "Ensuring Firefox is running..."
DHIS2_URL="http://localhost:8080"

if ! pgrep -f firefox > /dev/null; then
    su - ga -c "DISPLAY=:1 firefox '$DHIS2_URL' > /tmp/firefox_task.log 2>&1 &"
    sleep 8
else
    su - ga -c "DISPLAY=:1 firefox '$DHIS2_URL' > /dev/null 2>&1 &" 2>/dev/null || true
    sleep 4
fi

# Focus Firefox
WID=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i 'firefox\|mozilla' | awk '{print $1; exit}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
fi

take_screenshot /tmp/task_start_screenshot.png

echo "=== Measles Alert Task Setup Complete ==="