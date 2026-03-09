#!/bin/bash
# Export script for create_preventive_maintenance task
# - Queries SDP database for the created PM task
# - Exports details to JSON for the verifier

echo "=== Exporting Task Results ==="

source /workspace/scripts/task_utils.sh

# Record end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Capture final screenshot
take_screenshot /tmp/task_final.png

# 1. Get Initial Count
INITIAL_COUNT=$(cat /tmp/initial_pm_count.txt 2>/dev/null || echo "0")

# 2. Get Current Count
CURRENT_COUNT=$(sdp_db_exec "SELECT COUNT(*) FROM preventivemaintenance" 2>/dev/null || echo "0")
if ! [[ "$CURRENT_COUNT" =~ ^[0-9]+$ ]]; then CURRENT_COUNT=0; fi

# 3. Search for the specific PM task
# We look for the title specified in the task description
TARGET_NAME="Quarterly Data Center Server Health Check"

# Fetch record details (using ~ for ILIKE/regex match if possible, or simple equality)
# Note: SDP Postgres usually supports ILIKE.
PM_RECORD=$(sdp_db_exec "SELECT title, description, createdtime FROM preventivemaintenance WHERE title = '$TARGET_NAME' OR title ILIKE '%Quarterly Data Center%'" 2>/dev/null)

PM_FOUND="false"
PM_TITLE=""
PM_DESC=""
PM_CREATED_TIME="0"

if [ -n "$PM_RECORD" ]; then
    PM_FOUND="true"
    # Postgres output from sdp_db_exec usually pipe separated or similar depending on query
    # But sdp_db_exec uses -A -t (unaligned, tuples only), so usually pipe '|' separated by default
    PM_TITLE=$(echo "$PM_RECORD" | cut -d'|' -f1)
    PM_DESC=$(echo "$PM_RECORD" | cut -d'|' -f2)
    PM_CREATED_TIME=$(echo "$PM_RECORD" | cut -d'|' -f3)
fi

# 4. Check Schedule/Priority if possible
# These might be in linked tables like 'pmschedule' or 'workorder' (template)
# We'll do a best-effort query for priority/technician from the main table or linked template
# This query is hypothetical based on common schemas; if it fails, verifier will just use found/not found
DETAILS_QUERY="
SELECT 
    pd.priorityname, 
    ti.first_name 
FROM preventivemaintenance pm
LEFT JOIN prioritydefinition pd ON pm.priorityid = pd.priorityid
LEFT JOIN sdpuser ti ON pm.ownerid = ti.userid
WHERE pm.title = '$TARGET_NAME' OR pm.title ILIKE '%Quarterly Data Center%'
LIMIT 1
"
DETAILS_RECORD=$(sdp_db_exec "$DETAILS_QUERY" 2>/dev/null)
PM_PRIORITY=$(echo "$DETAILS_RECORD" | cut -d'|' -f1)
PM_TECHNICIAN=$(echo "$DETAILS_RECORD" | cut -d'|' -f2)

# 5. Check Schedule
# Look for schedule type or interval
SCHEDULE_INFO=$(sdp_db_exec "SELECT scheduletype, periodicity FROM pmschedule WHERE pmid IN (SELECT pmid FROM preventivemaintenance WHERE title = '$TARGET_NAME') LIMIT 1" 2>/dev/null)
PM_SCHEDULE_TYPE=$(echo "$SCHEDULE_INFO" | cut -d'|' -f1)
PM_PERIODICITY=$(echo "$SCHEDULE_INFO" | cut -d'|' -f2)

# Create JSON Result
TEMP_JSON=$(mktemp /tmp/pm_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "initial_count": $INITIAL_COUNT,
    "current_count": $CURRENT_COUNT,
    "pm_found": $PM_FOUND,
    "pm_title": "$(echo "$PM_TITLE" | sed 's/"/\\"/g')",
    "pm_description": "$(echo "$PM_DESC" | sed 's/"/\\"/g' | tr -d '\n')",
    "pm_created_time": "$PM_CREATED_TIME",
    "pm_priority": "$(echo "$PM_PRIORITY" | sed 's/"/\\"/g')",
    "pm_technician": "$(echo "$PM_TECHNICIAN" | sed 's/"/\\"/g')",
    "pm_schedule_type": "$(echo "$PM_SCHEDULE_TYPE" | sed 's/"/\\"/g')",
    "pm_periodicity": "$(echo "$PM_PERIODICITY" | sed 's/"/\\"/g')"
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result JSON content:"
cat /tmp/task_result.json
echo "=== Export Complete ==="