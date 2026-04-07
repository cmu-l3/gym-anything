#!/bin/bash
echo "=== Exporting create_support_group_and_assign_ticket results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/create_support_group_final.png

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Check Group
GROUP_DATA=$(vtiger_db_query "SELECT groupid, groupname FROM vtiger_groups WHERE groupname='Tier 2 Billing Escalations' LIMIT 1")
GROUP_FOUND="false"
GROUP_ID=""
GROUP_NAME=""
GROUP_USER_COUNT="0"

if [ -n "$GROUP_DATA" ]; then
    GROUP_FOUND="true"
    GROUP_ID=$(echo "$GROUP_DATA" | awk -F'\t' '{print $1}')
    GROUP_NAME=$(echo "$GROUP_DATA" | awk -F'\t' '{print $2}')
    
    if [ -n "$GROUP_ID" ]; then
        GROUP_USER_COUNT=$(vtiger_db_query "SELECT COUNT(*) FROM vtiger_users2group WHERE groupid=$GROUP_ID" | tr -d '[:space:]')
    fi
fi

# Check Ticket
TICKET_DATA=$(vtiger_db_query "SELECT t.ticketid, t.title, t.status, t.priority, c.smownerid, c.createdtime FROM vtiger_troubletickets t INNER JOIN vtiger_crmentity c ON t.ticketid=c.crmid WHERE t.title='Disputed Charge on Invoice #8472' AND c.deleted=0 LIMIT 1")

TICKET_FOUND="false"
T_ID=""
T_TITLE=""
T_STATUS=""
T_PRIORITY=""
T_OWNERID=""
T_CREATED=""

if [ -n "$TICKET_DATA" ]; then
    TICKET_FOUND="true"
    T_ID=$(echo "$TICKET_DATA" | awk -F'\t' '{print $1}')
    T_TITLE=$(echo "$TICKET_DATA" | awk -F'\t' '{print $2}')
    T_STATUS=$(echo "$TICKET_DATA" | awk -F'\t' '{print $3}')
    T_PRIORITY=$(echo "$TICKET_DATA" | awk -F'\t' '{print $4}')
    T_OWNERID=$(echo "$TICKET_DATA" | awk -F'\t' '{print $5}')
    T_CREATED=$(echo "$TICKET_DATA" | awk -F'\t' '{print $6}')
fi

RESULT_JSON=$(cat << JSONEOF
{
  "group_found": ${GROUP_FOUND},
  "group_id": "$(json_escape "${GROUP_ID:-}")",
  "group_name": "$(json_escape "${GROUP_NAME:-}")",
  "group_user_count": ${GROUP_USER_COUNT:-0},
  "ticket_found": ${TICKET_FOUND},
  "ticket_id": "$(json_escape "${T_ID:-}")",
  "ticket_title": "$(json_escape "${T_TITLE:-}")",
  "ticket_status": "$(json_escape "${T_STATUS:-}")",
  "ticket_priority": "$(json_escape "${T_PRIORITY:-}")",
  "ticket_owner_id": "$(json_escape "${T_OWNERID:-}")",
  "ticket_created_time": "$(json_escape "${T_CREATED:-}")",
  "task_start_time": ${TASK_START}
}
JSONEOF
)

safe_write_result "/tmp/create_support_group_result.json" "$RESULT_JSON"

echo "Result saved to /tmp/create_support_group_result.json"
echo "$RESULT_JSON"
echo "=== Export complete ==="