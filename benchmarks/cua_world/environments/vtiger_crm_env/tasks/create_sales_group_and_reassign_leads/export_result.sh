#!/bin/bash
echo "=== Exporting create_sales_group_and_reassign_leads results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# 1. Check if group exists
GROUP_ID=$(vtiger_db_query "SELECT groupid FROM vtiger_groups WHERE groupname='Enterprise Sales Team' LIMIT 1" | tr -d '[:space:]')

GROUP_EXISTS="false"
ADMIN_IN_GROUP="false"
TECH_REASSIGNED=0
NON_TECH_REASSIGNED=0

if [ -n "$GROUP_ID" ]; then
    GROUP_EXISTS="true"
    
    # 2. Check if admin is in the group
    ADMIN_ID=$(vtiger_db_query "SELECT id FROM vtiger_users WHERE user_name='admin' LIMIT 1" | tr -d '[:space:]')
    IN_GROUP_COUNT=$(vtiger_db_query "SELECT COUNT(*) FROM vtiger_users2group WHERE groupid=$GROUP_ID AND userid=$ADMIN_ID" | tr -d '[:space:]')
    if [ "$IN_GROUP_COUNT" -gt 0 ]; then
        ADMIN_IN_GROUP="true"
    fi

    # 3. Check leads reassigned to this group
    TECH_REASSIGNED=$(vtiger_db_query "SELECT COUNT(*) FROM vtiger_leaddetails l JOIN vtiger_crmentity c ON l.leadid = c.crmid WHERE l.industry='Technology' AND c.smownerid=$GROUP_ID" | tr -d '[:space:]')
    
    # 4. Check for collateral damage
    NON_TECH_REASSIGNED=$(vtiger_db_query "SELECT COUNT(*) FROM vtiger_leaddetails l JOIN vtiger_crmentity c ON l.leadid = c.crmid WHERE l.industry!='Technology' AND c.smownerid=$GROUP_ID" | tr -d '[:space:]')
fi

# Check if firefox was running
APP_RUNNING=$(pgrep -f "firefox" > /dev/null && echo "true" || echo "false")

# Generate JSON report
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_was_running": $APP_RUNNING,
    "group_exists": $GROUP_EXISTS,
    "admin_in_group": $ADMIN_IN_GROUP,
    "tech_leads_reassigned_count": ${TECH_REASSIGNED:-0},
    "non_tech_leads_reassigned_count": ${NON_TECH_REASSIGNED:-0},
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="