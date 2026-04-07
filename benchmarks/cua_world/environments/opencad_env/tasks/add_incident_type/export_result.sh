#!/bin/bash
echo "=== Exporting add_incident_type result ==="

source /workspace/scripts/task_utils.sh

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Get verification data
INITIAL_COUNT=$(cat /tmp/initial_incident_type_count.txt 2>/dev/null || echo "0")
BASELINE_MAX_ID=$(cat /tmp/initial_max_incident_type_id.txt 2>/dev/null || echo "0")
CURRENT_COUNT=$(opencad_db_query "SELECT COUNT(*) FROM incident_types")

# 3. Search for the specific record
# We look for "Equipment Rollover" (case-insensitive)
# We prioritize records created AFTER the task started (ID > BASELINE_MAX_ID)
FOUND_ID=""
FOUND_NAME=""
CREATED_DURING_TASK="false"

# Query for the specific name
# Note: Column name is likely 'incident_type' based on standard OpenCAD schema
RECORD=$(opencad_db_query "SELECT incident_type_id, incident_type FROM incident_types WHERE LOWER(incident_type) = 'equipment rollover' ORDER BY incident_type_id DESC LIMIT 1")

if [ -n "$RECORD" ]; then
    FOUND_ID=$(echo "$RECORD" | awk '{print $1}')
    # Extract name (everything after first column)
    FOUND_NAME=$(echo "$RECORD" | cut -f2-)
    
    if [ "$FOUND_ID" -gt "$BASELINE_MAX_ID" ]; then
        CREATED_DURING_TASK="true"
    fi
fi

# 4. JSON Export
# Use Python to generate safe JSON
cat << EOF > /tmp/task_result_temp.json
{
    "initial_count": ${INITIAL_COUNT:-0},
    "current_count": ${CURRENT_COUNT:-0},
    "found_record": {
        "exists": $( [ -n "$FOUND_ID" ] && echo "true" || echo "false" ),
        "id": ${FOUND_ID:-0},
        "name": "$(json_escape "${FOUND_NAME}")",
        "created_during_task": ${CREATED_DURING_TASK}
    },
    "baseline_max_id": ${BASELINE_MAX_ID:-0},
    "timestamp": "$(date -Iseconds)"
}
EOF

# Safe move
safe_write_result "$(cat /tmp/task_result_temp.json)" /tmp/task_result.json
rm -f /tmp/task_result_temp.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="