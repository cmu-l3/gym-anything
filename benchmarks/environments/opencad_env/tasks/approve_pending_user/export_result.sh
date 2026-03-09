#!/bin/bash
echo "=== Exporting approve_pending_user result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_final.png

INITIAL_APPROVED=$(cat /tmp/initial_approved_count 2>/dev/null || echo "0")
INITIAL_PENDING=$(cat /tmp/initial_pending_count 2>/dev/null || echo "0")
CURRENT_APPROVED=$(get_approved_user_count)
CURRENT_PENDING=$(get_pending_user_count)

# Check Sarah Mitchell's current status
SARAH_APPROVED=$(opencad_db_query "SELECT approved FROM users WHERE email='sarah.mitchell@opencad.local'")
SARAH_NAME=$(opencad_db_query "SELECT name FROM users WHERE email='sarah.mitchell@opencad.local'")
SARAH_ID=$(opencad_db_query "SELECT id FROM users WHERE email='sarah.mitchell@opencad.local'")

# Check if Sarah has been assigned to a department (moved from temp to permanent)
SARAH_DEPT=""
if [ -n "$SARAH_ID" ]; then
    SARAH_DEPT=$(opencad_db_query "SELECT d.department_name FROM user_departments ud JOIN departments d ON ud.department_id = d.department_id WHERE ud.user_id = ${SARAH_ID}" 2>/dev/null)
    if [ -z "$SARAH_DEPT" ]; then
        # Check temp table
        SARAH_DEPT=$(opencad_db_query "SELECT d.department_name FROM user_departments_temp udt JOIN departments d ON udt.department_id = d.department_id WHERE udt.user_id = ${SARAH_ID}" 2>/dev/null)
    fi
fi

RESULT_JSON=$(cat << EOF
{
    "initial_approved_count": ${INITIAL_APPROVED:-0},
    "initial_pending_count": ${INITIAL_PENDING:-0},
    "current_approved_count": ${CURRENT_APPROVED:-0},
    "current_pending_count": ${CURRENT_PENDING:-0},
    "sarah_mitchell": {
        "id": "$(json_escape "${SARAH_ID}")",
        "name": "$(json_escape "${SARAH_NAME}")",
        "approved": "$(json_escape "${SARAH_APPROVED}")",
        "department": "$(json_escape "${SARAH_DEPT}")"
    },
    "timestamp": "$(date -Iseconds)"
}
EOF
)

safe_write_result "$RESULT_JSON" /tmp/approve_pending_user_result.json

echo "Result saved to /tmp/approve_pending_user_result.json"
cat /tmp/approve_pending_user_result.json
echo "=== Export complete ==="
