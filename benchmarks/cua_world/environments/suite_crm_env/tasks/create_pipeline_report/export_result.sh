#!/bin/bash
echo "=== Exporting create_pipeline_report results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/create_pipeline_report_final.png

TASK_START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_REPORT_COUNT=$(cat /tmp/initial_report_count.txt 2>/dev/null || echo "0")
CURRENT_REPORT_COUNT=$(suitecrm_db_query "SELECT COUNT(*) FROM aor_reports WHERE deleted=0" | tr -d '[:space:]')

# Query for the target report
REPORT_DATA=$(suitecrm_db_query "SELECT id, name, report_module, UNIX_TIMESTAMP(date_entered) FROM aor_reports WHERE name='Weekly Pipeline by Stage' AND deleted=0 LIMIT 1")

REPORT_FOUND="false"
R_ID=""
R_NAME=""
R_MOD=""
R_DATE="0"
FIELD_COUNT=0
GROUP_COUNT=0

if [ -n "$REPORT_DATA" ]; then
    REPORT_FOUND="true"
    R_ID=$(echo "$REPORT_DATA" | awk -F'\t' '{print $1}')
    R_NAME=$(echo "$REPORT_DATA" | awk -F'\t' '{print $2}')
    R_MOD=$(echo "$REPORT_DATA" | awk -F'\t' '{print $3}')
    R_DATE=$(echo "$REPORT_DATA" | awk -F'\t' '{print $4}')
    
    # Query for associated fields
    FIELD_COUNT=$(suitecrm_db_query "SELECT COUNT(*) FROM aor_fields WHERE aor_report_id='${R_ID}' AND deleted=0" | tr -d '[:space:]')
    
    # Query for grouping (check both group_by and group_display flags as SuiteCRM versions vary slightly)
    GROUP_COUNT=$(suitecrm_db_query "SELECT COUNT(*) FROM aor_fields WHERE aor_report_id='${R_ID}' AND (group_by=1 OR group_by='1' OR group_display=1 OR group_display='1') AND deleted=0" | tr -d '[:space:]')
fi

# Ensure counts are integers
FIELD_COUNT=${FIELD_COUNT:-0}
GROUP_COUNT=${GROUP_COUNT:-0}

RESULT_JSON=$(cat << JSONEOF
{
  "task_start_time": ${TASK_START_TIME},
  "report_found": ${REPORT_FOUND},
  "report_id": "$(json_escape "${R_ID:-}")",
  "name": "$(json_escape "${R_NAME:-}")",
  "report_module": "$(json_escape "${R_MOD:-}")",
  "date_entered": ${R_DATE:-0},
  "field_count": ${FIELD_COUNT},
  "group_count": ${GROUP_COUNT},
  "initial_count": ${INITIAL_REPORT_COUNT},
  "current_count": ${CURRENT_REPORT_COUNT}
}
JSONEOF
)

safe_write_result "/tmp/create_pipeline_report_result.json" "$RESULT_JSON"

echo "Result saved to /tmp/create_pipeline_report_result.json"
echo "$RESULT_JSON"
echo "=== create_pipeline_report export complete ==="