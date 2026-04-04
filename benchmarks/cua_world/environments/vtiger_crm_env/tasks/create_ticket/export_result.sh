#!/bin/bash
echo "=== Exporting create_ticket results ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/create_ticket_final.png

INITIAL_TICKET_COUNT=$(cat /tmp/initial_ticket_count.txt 2>/dev/null || echo "0")
CURRENT_TICKET_COUNT=$(get_ticket_count)

TICKET_DATA=$(vtiger_db_query "SELECT t.ticketid, t.title, t.status, t.priority, t.severity, t.category FROM vtiger_troubletickets t WHERE t.title='API gateway returning 503 errors under load' LIMIT 1")

TICKET_FOUND="false"
if [ -n "$TICKET_DATA" ]; then
    TICKET_FOUND="true"
    T_ID=$(echo "$TICKET_DATA" | awk -F'\t' '{print $1}')
    T_TITLE=$(echo "$TICKET_DATA" | awk -F'\t' '{print $2}')
    T_STATUS=$(echo "$TICKET_DATA" | awk -F'\t' '{print $3}')
    T_PRIORITY=$(echo "$TICKET_DATA" | awk -F'\t' '{print $4}')
    T_SEVERITY=$(echo "$TICKET_DATA" | awk -F'\t' '{print $5}')
    T_CATEGORY=$(echo "$TICKET_DATA" | awk -F'\t' '{print $6}')
fi

RESULT_JSON=$(cat << JSONEOF
{
  "ticket_found": ${TICKET_FOUND},
  "ticket_id": "$(json_escape "${T_ID:-}")",
  "title": "$(json_escape "${T_TITLE:-}")",
  "status": "$(json_escape "${T_STATUS:-}")",
  "priority": "$(json_escape "${T_PRIORITY:-}")",
  "severity": "$(json_escape "${T_SEVERITY:-}")",
  "category": "$(json_escape "${T_CATEGORY:-}")",
  "initial_count": ${INITIAL_TICKET_COUNT},
  "current_count": ${CURRENT_TICKET_COUNT}
}
JSONEOF
)

safe_write_result "/tmp/create_ticket_result.json" "$RESULT_JSON"

echo "Result saved to /tmp/create_ticket_result.json"
echo "$RESULT_JSON"
echo "=== create_ticket export complete ==="
