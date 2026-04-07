#!/bin/bash
echo "=== Exporting go_on_duty_fire result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Query the units table for the Admin user (ID 2)
# We expect to find a record if they went on duty
UNIT_DATA=$(opencad_db_query "SELECT id, department_id, status, updated_at FROM units WHERE user_id=2 LIMIT 1")

UNIT_FOUND="false"
UNIT_ID=""
DEPT_ID=""
STATUS=""
UPDATED_AT=""

if [ -n "$UNIT_DATA" ]; then
    UNIT_FOUND="true"
    UNIT_ID=$(echo "$UNIT_DATA" | cut -f1)
    DEPT_ID=$(echo "$UNIT_DATA" | cut -f2)
    STATUS=$(echo "$UNIT_DATA" | cut -f3)
    UPDATED_AT=$(echo "$UNIT_DATA" | cut -f4)
fi

# Get Department Name if we have an ID
DEPT_NAME=""
if [ -n "$DEPT_ID" ]; then
    DEPT_NAME=$(opencad_db_query "SELECT department_name FROM departments WHERE department_id=${DEPT_ID}")
fi

# Prepare JSON result
RESULT_JSON=$(cat << EOF
{
    "unit_found": ${UNIT_FOUND},
    "unit": {
        "id": "$(json_escape "${UNIT_ID}")",
        "department_id": "$(json_escape "${DEPT_ID}")",
        "department_name": "$(json_escape "${DEPT_NAME}")",
        "status": "$(json_escape "${STATUS}")",
        "updated_at": "$(json_escape "${UPDATED_AT}")"
    },
    "timestamp": "$(date -Iseconds)"
}
EOF
)

safe_write_result "$RESULT_JSON" /tmp/go_on_duty_fire_result.json

echo "Result saved to /tmp/go_on_duty_fire_result.json"
cat /tmp/go_on_duty_fire_result.json
echo "=== Export complete ==="