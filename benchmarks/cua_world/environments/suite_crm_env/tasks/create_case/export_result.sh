#!/bin/bash
echo "=== Exporting create_case results ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/create_case_final.png

INITIAL_CASE_COUNT=$(cat /tmp/initial_case_count.txt 2>/dev/null || echo "0")
CURRENT_CASE_COUNT=$(get_case_count)

CASE_DATA=$(suitecrm_db_query "SELECT id, name, status, priority, type, case_number, description FROM cases WHERE name='Data pipeline latency spike after v4.1 upgrade' AND deleted=0 LIMIT 1")

CASE_FOUND="false"
if [ -n "$CASE_DATA" ]; then
    CASE_FOUND="true"
    CS_ID=$(echo "$CASE_DATA" | awk -F'\t' '{print $1}')
    CS_NAME=$(echo "$CASE_DATA" | awk -F'\t' '{print $2}')
    CS_STATUS=$(echo "$CASE_DATA" | awk -F'\t' '{print $3}')
    CS_PRIORITY=$(echo "$CASE_DATA" | awk -F'\t' '{print $4}')
    CS_TYPE=$(echo "$CASE_DATA" | awk -F'\t' '{print $5}')
    CS_NUMBER=$(echo "$CASE_DATA" | awk -F'\t' '{print $6}')
fi

RESULT_JSON=$(cat << JSONEOF
{
  "case_found": ${CASE_FOUND},
  "case_id": "$(json_escape "${CS_ID:-}")",
  "name": "$(json_escape "${CS_NAME:-}")",
  "status": "$(json_escape "${CS_STATUS:-}")",
  "priority": "$(json_escape "${CS_PRIORITY:-}")",
  "type": "$(json_escape "${CS_TYPE:-}")",
  "case_number": "$(json_escape "${CS_NUMBER:-}")",
  "initial_count": ${INITIAL_CASE_COUNT},
  "current_count": ${CURRENT_CASE_COUNT}
}
JSONEOF
)

safe_write_result "/tmp/create_case_result.json" "$RESULT_JSON"

echo "Result saved to /tmp/create_case_result.json"
echo "$RESULT_JSON"
echo "=== create_case export complete ==="
