#!/bin/bash
echo "=== Exporting revoke_department_access result ==="

source /workspace/scripts/task_utils.sh

# Capture final visual state
take_screenshot /tmp/task_final.png

# 1. Get IDs again to verify against current state
JAMES_ID=$(opencad_db_query "SELECT id FROM users WHERE email='james.rodriguez@opencad.local' LIMIT 1")
POLICE_ID=$(opencad_db_query "SELECT department_id FROM departments WHERE department_name='Police' LIMIT 1")
CIVILIAN_ID=$(opencad_db_query "SELECT department_id FROM departments WHERE department_name='Civilian' LIMIT 1")

# 2. Check User Existence (Anti-Gaming: Did they just delete the user?)
USER_EXISTS="false"
if [ -n "$JAMES_ID" ]; then
    USER_EXISTS="true"
fi

# 3. Check Department Links
POLICE_ACCESS_COUNT=0
CIVILIAN_ACCESS_COUNT=0

if [ "$USER_EXISTS" = "true" ]; then
    # Check Police Access (Should be 0 if successful)
    POLICE_ACCESS_COUNT=$(opencad_db_query "SELECT COUNT(*) FROM user_departments WHERE user_id=${JAMES_ID} AND department_id=${POLICE_ID}")
    
    # Check Civilian Access (Should be > 0 if successful)
    CIVILIAN_ACCESS_COUNT=$(opencad_db_query "SELECT COUNT(*) FROM user_departments WHERE user_id=${JAMES_ID} AND department_id=${CIVILIAN_ID}")
fi

# 4. Check for Total Destruction (Did they delete ALL departments for him?)
TOTAL_DEPTS=$(opencad_db_query "SELECT COUNT(*) FROM user_departments WHERE user_id=${JAMES_ID}")

# 5. Check if Admin is still logged in or app is running (basic health check)
APP_RUNNING="false"
if pgrep -f "firefox" > /dev/null; then
    APP_RUNNING="true"
fi

# 6. Generate JSON Result
RESULT_JSON=$(cat << EOF
{
    "user_exists": ${USER_EXISTS},
    "user_id": "$(json_escape "${JAMES_ID}")",
    "police_id": "$(json_escape "${POLICE_ID}")",
    "civilian_id": "$(json_escape "${CIVILIAN_ID}")",
    "police_access_count": ${POLICE_ACCESS_COUNT:-0},
    "civilian_access_count": ${CIVILIAN_ACCESS_COUNT:-0},
    "total_departments_count": ${TOTAL_DEPTS:-0},
    "app_running": ${APP_RUNNING},
    "timestamp": "$(date -Iseconds)"
}
EOF
)

safe_write_result "$RESULT_JSON" /tmp/revoke_department_access_result.json

echo "Result saved to /tmp/revoke_department_access_result.json"
cat /tmp/revoke_department_access_result.json
echo "=== Export complete ==="