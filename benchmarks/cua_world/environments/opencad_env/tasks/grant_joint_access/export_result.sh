#!/bin/bash
echo "=== Exporting grant_joint_access result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Get Task Start Time
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_COUNT=$(cat /tmp/initial_dept_count.txt 2>/dev/null || echo "0")

# Target User ID is 3 (Dispatch Officer)
USER_ID=3

# Get current department assignments
# Returns space-separated list of IDs, e.g., "1 3 4"
DEPT_IDS_STR=$(opencad_db_query "SELECT department_id FROM user_departments WHERE user_id = ${USER_ID} ORDER BY department_id ASC")

# Convert newlines/spaces to JSON array
# Example output from query might be multiline, tr makes it single line space separated
DEPT_IDS_CLEAN=$(echo "$DEPT_IDS_STR" | tr '\n' ' ' | sed 's/ $//')
# Construct JSON array: [1, 3, 4]
JSON_ARRAY="["
FIRST=true
for id in $DEPT_IDS_CLEAN; do
    if [ "$FIRST" = true ]; then
        JSON_ARRAY="${JSON_ARRAY}${id}"
        FIRST=false
    else
        JSON_ARRAY="${JSON_ARRAY}, ${id}"
    fi
done
JSON_ARRAY="${JSON_ARRAY}]"

# Get current count
CURRENT_COUNT=$(opencad_db_query "SELECT COUNT(*) FROM user_departments WHERE user_id = ${USER_ID}")

# Check for specific departments
HAS_COMMS="false"
HAS_HIGHWAY="false"
HAS_SHERIFF="false"

# Check ID 1 (Communications)
if echo "$DEPT_IDS_CLEAN" | grep -q "\b1\b"; then HAS_COMMS="true"; fi
# Check ID 3 (Highway)
if echo "$DEPT_IDS_CLEAN" | grep -q "\b3\b"; then HAS_HIGHWAY="true"; fi
# Check ID 4 (Sheriff)
if echo "$DEPT_IDS_CLEAN" | grep -q "\b4\b"; then HAS_SHERIFF="true"; fi

# Construct Result JSON
RESULT_JSON=$(cat << EOF
{
    "user_id": ${USER_ID},
    "task_start_timestamp": ${TASK_START},
    "initial_dept_count": ${INITIAL_COUNT:-0},
    "current_dept_count": ${CURRENT_COUNT:-0},
    "department_ids": ${JSON_ARRAY},
    "has_communications": ${HAS_COMMS},
    "has_highway": ${HAS_HIGHWAY},
    "has_sheriff": ${HAS_SHERIFF},
    "timestamp": "$(date -Iseconds)"
}
EOF
)

safe_write_result "$RESULT_JSON" /tmp/grant_joint_access_result.json

echo "Result saved to /tmp/grant_joint_access_result.json"
cat /tmp/grant_joint_access_result.json
echo "=== Export complete ==="