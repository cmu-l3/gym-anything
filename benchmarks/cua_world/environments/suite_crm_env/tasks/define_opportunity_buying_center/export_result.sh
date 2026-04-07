#!/bin/bash
echo "=== Exporting define_opportunity_buying_center results ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Capture final visual state
take_screenshot /tmp/task_final.png

# Query the opportunities_contacts junction table
REL_DATA=$(suitecrm_db_query "SELECT c.first_name, c.last_name, oc.contact_role, UNIX_TIMESTAMP(oc.date_modified) FROM opportunities_contacts oc JOIN contacts c ON oc.contact_id = c.id WHERE oc.opportunity_id = 'opp-apex-001' AND oc.deleted = 0")

JSON_ROWS="[]"
if [ -n "$REL_DATA" ]; then
    JSON_ROWS="["
    FIRST="true"
    while IFS=$'\t' read -r fname lname role mtime; do
        if [ "$FIRST" = "true" ]; then
            FIRST="false"
        else
            JSON_ROWS="${JSON_ROWS},"
        fi
        
        if [ "$role" = "NULL" ]; then role=""; fi
        
        # Clean potential carriage returns
        fname=$(echo "$fname" | tr -d '\r')
        lname=$(echo "$lname" | tr -d '\r')
        role=$(echo "$role" | tr -d '\r')
        mtime=$(echo "$mtime" | tr -d '\r')
        
        JSON_ROWS="${JSON_ROWS}{\"first_name\":\"$(json_escape "$fname")\", \"last_name\":\"$(json_escape "$lname")\", \"role\":\"$(json_escape "$role")\", \"mtime\":${mtime:-0}}"
    done < <(echo "$REL_DATA")
    JSON_ROWS="${JSON_ROWS}]"
fi

RESULT_JSON=$(cat << JSONEOF
{
  "task_start": $TASK_START,
  "relationships": $JSON_ROWS
}
JSONEOF
)

safe_write_result "/tmp/task_result.json" "$RESULT_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== export complete ==="