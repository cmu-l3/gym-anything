#!/bin/bash
echo "=== Exporting create_pipeline_report results ==="

source /workspace/scripts/task_utils.sh

# Capture final screenshot
take_screenshot /tmp/task_final_state.png

# Load initial state variables
INITIAL_MAX_REPORT_ID=$(cat /tmp/initial_max_report_id.txt 2>/dev/null || echo "0")
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Query Vtiger Database for the target report
REPORT_DATA=$(vtiger_db_query "SELECT reportid, reportname, reporttype FROM vtiger_report WHERE reportname='Q4 Pipeline Summary' LIMIT 1")

REPORT_FOUND="false"
R_ID="0"
R_NAME=""
R_TYPE=""
R_MODULE=""
R_COLUMNS=""
R_GROUP_BY=""
R_CONDITIONS=""
R_CONDITIONS_ADV=""
NEWLY_CREATED="false"

if [ -n "$REPORT_DATA" ]; then
    REPORT_FOUND="true"
    R_ID=$(echo "$REPORT_DATA" | awk -F'\t' '{print $1}')
    R_NAME=$(echo "$REPORT_DATA" | awk -F'\t' '{print $2}')
    R_TYPE=$(echo "$REPORT_DATA" | awk -F'\t' '{print $3}')
    
    # Check if newly created
    if [ "$R_ID" -gt "$INITIAL_MAX_REPORT_ID" ]; then
        NEWLY_CREATED="true"
    fi

    # Query associated module
    R_MODULE=$(vtiger_db_query "SELECT primarymodule FROM vtiger_reportmodules WHERE reportmodulesid=$R_ID LIMIT 1" | tr -d '\n')
    
    # Query selected columns
    R_COLUMNS=$(vtiger_db_query "SELECT GROUP_CONCAT(columnname SEPARATOR '||') FROM vtiger_selectcolumn WHERE queryid=$R_ID" | tr -d '\n')
    
    # Query group by fields
    R_GROUP_BY=$(vtiger_db_query "SELECT GROUP_CONCAT(sort_colname SEPARATOR '||') FROM vtiger_reportgroupbycolumn WHERE reportid=$R_ID" | tr -d '\n')
    
    # Query conditions (both standard and advanced criteria tables)
    R_CONDITIONS=$(vtiger_db_query "SELECT GROUP_CONCAT(CONCAT(columnname, '|', comparator, '|', value) SEPARATOR '||') FROM vtiger_relcriteria WHERE queryid=$R_ID" | tr -d '\n')
    R_CONDITIONS_ADV=$(vtiger_db_query "SELECT GROUP_CONCAT(CONCAT(columnname, '|', comparator, '|', value) SEPARATOR '||') FROM vtiger_advcriteria WHERE queryid=$R_ID" | tr -d '\n')
fi

# Construct JSON output safely using task_utils json_escape
RESULT_JSON=$(cat << JSONEOF
{
  "task_start_time": ${TASK_START},
  "initial_max_report_id": ${INITIAL_MAX_REPORT_ID},
  "report_found": ${REPORT_FOUND},
  "newly_created": ${NEWLY_CREATED},
  "report_id": ${R_ID},
  "report_name": "$(json_escape "${R_NAME}")",
  "report_type": "$(json_escape "${R_TYPE}")",
  "primary_module": "$(json_escape "${R_MODULE}")",
  "columns": "$(json_escape "${R_COLUMNS}")",
  "group_by": "$(json_escape "${R_GROUP_BY}")",
  "conditions": "$(json_escape "${R_CONDITIONS}")",
  "conditions_adv": "$(json_escape "${R_CONDITIONS_ADV}")"
}
JSONEOF
)

# Write result to file safely
safe_write_result "/tmp/task_result.json" "$RESULT_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== create_pipeline_report export complete ==="