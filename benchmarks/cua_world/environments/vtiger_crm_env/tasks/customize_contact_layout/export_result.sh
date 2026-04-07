#!/bin/bash
echo "=== Exporting customize_contact_layout results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/customize_contact_layout_final.png

# Record end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Get the Tab ID for the Contacts module
TABID=$(vtiger_db_query "SELECT tabid FROM vtiger_tab WHERE name='Contacts' LIMIT 1" | tr -d '[:space:]')
TABID=${TABID:-4}

# 2. Query the current state of the modified fields
TITLE_SUMMARY=$(vtiger_db_query "SELECT summaryfield FROM vtiger_field WHERE fieldname='title' AND tabid=$TABID" | tr -d '[:space:]')
MOBILE_SUMMARY=$(vtiger_db_query "SELECT summaryfield FROM vtiger_field WHERE fieldname='mobile' AND tabid=$TABID" | tr -d '[:space:]')
DEPT_SUMMARY=$(vtiger_db_query "SELECT summaryfield FROM vtiger_field WHERE fieldname='department' AND tabid=$TABID" | tr -d '[:space:]')
EMAIL_TYPE=$(vtiger_db_query "SELECT typeofdata FROM vtiger_field WHERE fieldname='email' AND tabid=$TABID" | tr -d '[:space:]')

# Handle empty responses
TITLE_SUMMARY=${TITLE_SUMMARY:-0}
MOBILE_SUMMARY=${MOBILE_SUMMARY:-0}
DEPT_SUMMARY=${DEPT_SUMMARY:-0}
EMAIL_TYPE=${EMAIL_TYPE:-"unknown"}

echo "Extracted DB Values:"
echo "Title Summary: $TITLE_SUMMARY"
echo "Mobile Summary: $MOBILE_SUMMARY"
echo "Dept Summary: $DEPT_SUMMARY"
echo "Email TypeOfData: $EMAIL_TYPE"

# Generate JSON payload safely
RESULT_JSON=$(cat << JSONEOF
{
  "task_start": $TASK_START,
  "task_end": $TASK_END,
  "title_summary": "$TITLE_SUMMARY",
  "mobile_summary": "$MOBILE_SUMMARY",
  "department_summary": "$DEPT_SUMMARY",
  "email_typeofdata": "$EMAIL_TYPE"
}
JSONEOF
)

safe_write_result "/tmp/customize_contact_layout_result.json" "$RESULT_JSON"

echo "Result saved to /tmp/customize_contact_layout_result.json"
echo "$RESULT_JSON"
echo "=== customize_contact_layout export complete ==="