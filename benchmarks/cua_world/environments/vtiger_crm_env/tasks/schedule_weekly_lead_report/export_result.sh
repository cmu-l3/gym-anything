#!/bin/bash
echo "=== Exporting schedule_weekly_lead_report results ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/schedule_report_final.png

INITIAL_REPORT_MAX_ID=$(cat /tmp/initial_report_max_id.txt 2>/dev/null || echo "0")

REPORT_DATA=$(vtiger_db_query "SELECT reportid, reportname, primarymodule, reporttype FROM vtiger_report WHERE reportname='Weekly Lead Source Summary' ORDER BY reportid DESC LIMIT 1")

REPORT_FOUND="false"
R_ID="0"
R_NAME=""
R_MODULE=""
R_TYPE=""
GROUPING_COLS=""
SCH_ACTIVE="0"
SCH_TIME=""
SCH_DAY=""
SCH_TYPE=""
SCH_RECIPIENTS=""

if [ -n "$REPORT_DATA" ]; then
    REPORT_FOUND="true"
    R_ID=$(echo "$REPORT_DATA" | awk -F'\t' '{print $1}')
    R_NAME=$(echo "$REPORT_DATA" | awk -F'\t' '{print $2}')
    R_MODULE=$(echo "$REPORT_DATA" | awk -F'\t' '{print $3}')
    R_TYPE=$(echo "$REPORT_DATA" | awk -F'\t' '{print $4}')

    # Get grouping columns (checking both tables used in different Vtiger versions)
    GROUPING_COLS_1=$(vtiger_db_query "SELECT columnname FROM vtiger_reportsortcol WHERE reportid=$R_ID" | tr '\n' ',' || echo "")
    GROUPING_COLS_2=$(vtiger_db_query "SELECT columnname FROM vtiger_reportgroupbycolumn WHERE reportid=$R_ID" | tr '\n' ',' || echo "")
    GROUPING_COLS="${GROUPING_COLS_1}${GROUPING_COLS_2}"

    # Get schedule details
    SCH_DATA=$(vtiger_db_query "SELECT isactive, schtime, schdayoftheweek, schtype, recipients FROM vtiger_scheduled_reports WHERE reportid=$R_ID LIMIT 1")
    if [ -n "$SCH_DATA" ]; then
        SCH_ACTIVE=$(echo "$SCH_DATA" | awk -F'\t' '{print $1}')
        SCH_TIME=$(echo "$SCH_DATA" | awk -F'\t' '{print $2}')
        SCH_DAY=$(echo "$SCH_DATA" | awk -F'\t' '{print $3}')
        SCH_TYPE=$(echo "$SCH_DATA" | awk -F'\t' '{print $4}')
        SCH_RECIPIENTS=$(echo "$SCH_DATA" | awk -F'\t' '{print $5}')
    fi
fi

RESULT_JSON=$(cat << JSONEOF
{
  "report_found": ${REPORT_FOUND},
  "report_id": ${R_ID:-0},
  "report_name": "$(json_escape "${R_NAME:-}")",
  "primary_module": "$(json_escape "${R_MODULE:-}")",
  "report_type": "$(json_escape "${R_TYPE:-}")",
  "grouping_cols": "$(json_escape "${GROUPING_COLS:-}")",
  "sch_active": "$(json_escape "${SCH_ACTIVE:-0}")",
  "sch_time": "$(json_escape "${SCH_TIME:-}")",
  "sch_day": "$(json_escape "${SCH_DAY:-}")",
  "sch_type": "$(json_escape "${SCH_TYPE:-}")",
  "sch_recipients": "$(json_escape "${SCH_RECIPIENTS:-}")",
  "initial_max_id": ${INITIAL_REPORT_MAX_ID}
}
JSONEOF
)

safe_write_result "/tmp/schedule_report_result.json" "$RESULT_JSON"

echo "Result saved to /tmp/schedule_report_result.json"
echo "$RESULT_JSON"
echo "=== schedule_weekly_lead_report export complete ==="