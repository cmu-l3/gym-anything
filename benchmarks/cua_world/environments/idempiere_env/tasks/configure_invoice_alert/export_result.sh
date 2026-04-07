#!/bin/bash
echo "=== Exporting configure_invoice_alert result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# 1. Query the Database for the Alert Header
# We look for the specific name created in the GardenWorld client
CLIENT_ID=$(get_gardenworld_client_id)
echo "Querying for Alert 'High Value Purchase' in Client $CLIENT_ID..."

# Get Alert Header details
# Use separator | for fields
ALERT_DATA=$(idempiere_query "SELECT ad_alert_id, name, alertsubject, selectclause, isactive FROM ad_alert WHERE name='High Value Purchase' AND ad_client_id=$CLIENT_ID ORDER BY created DESC LIMIT 1" 2>/dev/null)

ALERT_FOUND="false"
ALERT_ID=""
ALERT_NAME=""
ALERT_SUBJECT=""
SELECT_CLAUSE=""
ALERT_ACTIVE=""

if [ -n "$ALERT_DATA" ]; then
    ALERT_FOUND="true"
    ALERT_ID=$(echo "$ALERT_DATA" | cut -d'|' -f1)
    ALERT_NAME=$(echo "$ALERT_DATA" | cut -d'|' -f2)
    ALERT_SUBJECT=$(echo "$ALERT_DATA" | cut -d'|' -f3)
    SELECT_CLAUSE=$(echo "$ALERT_DATA" | cut -d'|' -f4)
    ALERT_ACTIVE=$(echo "$ALERT_DATA" | cut -d'|' -f5)
fi

# 2. Query for the Recipient if Alert found
RECIPIENT_FOUND="false"
RECIPIENT_USER=""

if [ "$ALERT_FOUND" = "true" ] && [ -n "$ALERT_ID" ]; then
    echo "Checking recipients for Alert ID $ALERT_ID..."
    # Join with AD_User to get the name
    RECIPIENT_DATA=$(idempiere_query "SELECT u.name FROM ad_alertrecipient ar JOIN ad_user u ON ar.ad_user_id = u.ad_user_id WHERE ar.ad_alert_id=$ALERT_ID AND ar.isactive='Y' LIMIT 1" 2>/dev/null)
    
    if [ -n "$RECIPIENT_DATA" ]; then
        RECIPIENT_FOUND="true"
        RECIPIENT_USER="$RECIPIENT_DATA"
    fi
fi

# 3. Create JSON Result
# Using jq if available would be cleaner, but using python for robust JSON creation to avoid shell escaping hell
python3 -c "
import json
import sys

data = {
    'task_start': $TASK_START,
    'task_end': $TASK_END,
    'alert_found': $ALERT_FOUND,
    'alert_id': '$ALERT_ID',
    'alert_name': '''$ALERT_NAME''',
    'alert_subject': '''$ALERT_SUBJECT''',
    'select_clause': '''$SELECT_CLAUSE''',
    'alert_active': '$ALERT_ACTIVE',
    'recipient_found': $RECIPIENT_FOUND,
    'recipient_user': '''$RECIPIENT_USER''',
    'screenshot_path': '/tmp/task_final.png'
}
print(json.dumps(data, indent=2))
" > /tmp/task_result.json

# Move to final location (ensure permissions)
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="