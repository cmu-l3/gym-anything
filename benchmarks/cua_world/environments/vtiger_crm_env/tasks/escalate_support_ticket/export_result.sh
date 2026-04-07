#!/bin/bash
echo "=== Exporting escalate_support_ticket results ==="

source /workspace/scripts/task_utils.sh

# Capture final screenshot
take_screenshot /tmp/escalate_ticket_final.png

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TARGET_TICKET_ID=$(cat /tmp/target_ticket_id.txt 2>/dev/null || echo "99901")

# Fetch ticket state
TICKET_DATA=$(vtiger_db_query "SELECT t.ticketid, t.title, t.priority, e.smownerid, UNIX_TIMESTAMP(e.modifiedtime) FROM vtiger_troubletickets t JOIN vtiger_crmentity e ON t.ticketid = e.crmid WHERE t.title='Payment Gateway Integration Failure' AND e.deleted=0 ORDER BY t.ticketid DESC LIMIT 1")

TICKET_FOUND="false"
T_ID=""
T_PRIORITY=""
T_OWNER=""
OWNER_NAME=""
T_MODIFIED="0"
COMMENT_TEXT=""

if [ -n "$TICKET_DATA" ]; then
    TICKET_FOUND="true"
    T_ID=$(echo "$TICKET_DATA" | awk -F'\t' '{print $1}')
    T_PRIORITY=$(echo "$TICKET_DATA" | awk -F'\t' '{print $3}')
    T_OWNER=$(echo "$TICKET_DATA" | awk -F'\t' '{print $4}')
    T_MODIFIED=$(echo "$TICKET_DATA" | awk -F'\t' '{print $5}')
    
    # Resolve owner name (User vs Group)
    IS_GROUP=$(vtiger_db_query "SELECT COUNT(*) FROM vtiger_groups WHERE groupid=$T_OWNER" | tr -d '[:space:]')
    if [ "$IS_GROUP" -gt 0 ]; then
        OWNER_NAME=$(vtiger_db_query "SELECT groupname FROM vtiger_groups WHERE groupid=$T_OWNER LIMIT 1")
    else
        OWNER_NAME=$(vtiger_db_query "SELECT user_name FROM vtiger_users WHERE id=$T_OWNER LIMIT 1")
    fi
    
    # Fetch latest comment added during the task session
    COMMENT_TEXT=$(vtiger_db_query "SELECT c.commentcontent FROM vtiger_modcomments c JOIN vtiger_crmentity e ON c.modcommentsid = e.crmid WHERE c.related_to=$T_ID AND e.deleted=0 AND UNIX_TIMESTAMP(e.createdtime) >= $TASK_START ORDER BY e.createdtime DESC LIMIT 1")
fi

RESULT_JSON=$(cat << JSONEOF
{
  "ticket_found": ${TICKET_FOUND},
  "ticket_id": "$(json_escape "${T_ID:-}")",
  "priority": "$(json_escape "${T_PRIORITY:-}")",
  "owner_id": "$(json_escape "${T_OWNER:-}")",
  "owner_name": "$(json_escape "${OWNER_NAME:-}")",
  "modified_time": ${T_MODIFIED:-0},
  "task_start_time": ${TASK_START:-0},
  "comment_added": "$(json_escape "${COMMENT_TEXT:-}")"
}
JSONEOF
)

safe_write_result "/tmp/task_result.json" "$RESULT_JSON"

echo "Result saved to /tmp/task_result.json"
echo "$RESULT_JSON"
echo "=== escalate_support_ticket export complete ==="