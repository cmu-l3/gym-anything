#!/bin/bash
echo "=== Exporting create_custom_listview results ==="

source /workspace/scripts/task_utils.sh

# Record end state screenshot
take_screenshot /tmp/create_custom_listview_final.png

# Retrieve initial state data
INITIAL_MAX_CVID=$(cat /tmp/initial_max_cvid.txt 2>/dev/null || echo "0")

# Query the database for the newly created view
VIEW_DATA=$(vtiger_db_query "SELECT cvid, viewname, status FROM vtiger_customview WHERE viewname='New York Contacts' AND entitytype='Contacts' ORDER BY cvid DESC LIMIT 1")

if [ -n "$VIEW_DATA" ]; then
    VIEW_FOUND="true"
    CVID=$(echo "$VIEW_DATA" | awk -F'\t' '{print $1}')
    VIEW_NAME=$(echo "$VIEW_DATA" | awk -F'\t' '{print $2}')
    VIEW_STATUS=$(echo "$VIEW_DATA" | awk -F'\t' '{print $3}')
    
    # Retrieve the advanced filter conditions associated with this view
    # Format: columnname|comparator|value;columnname|comparator|value...
    FILTERS_TEXT=$(vtiger_db_query "SELECT CONCAT(IFNULL(columnname,''), '|', IFNULL(comparator,''), '|', IFNULL(value,'')) FROM vtiger_cvadvfilter WHERE cvid=$CVID" | tr '\n' ';' | sed 's/"/\\"/g' | sed 's/;$//')
    
    # Retrieve the configured display columns associated with this view
    # Format: columnname;columnname;columnname...
    COLUMNS_TEXT=$(vtiger_db_query "SELECT columnname FROM vtiger_cvcolumnlist WHERE cvid=$CVID" | tr '\n' ';' | sed 's/"/\\"/g' | sed 's/;$//')
else
    VIEW_FOUND="false"
    CVID="0"
    VIEW_NAME=""
    VIEW_STATUS=""
    FILTERS_TEXT=""
    COLUMNS_TEXT=""
fi

# Build JSON result safely
RESULT_JSON=$(cat << JSONEOF
{
  "view_found": ${VIEW_FOUND},
  "cvid": ${CVID},
  "initial_max_cvid": ${INITIAL_MAX_CVID},
  "view_name": "$(json_escape "${VIEW_NAME}")",
  "view_status": "$(json_escape "${VIEW_STATUS}")",
  "filters": "$(json_escape "${FILTERS_TEXT}")",
  "columns": "$(json_escape "${COLUMNS_TEXT}")"
}
JSONEOF
)

# Save result JSON to expected location
safe_write_result "/tmp/create_custom_listview_result.json" "$RESULT_JSON"

echo "Result saved to /tmp/create_custom_listview_result.json"
echo "$RESULT_JSON"
echo "=== create_custom_listview export complete ==="