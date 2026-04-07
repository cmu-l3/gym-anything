#!/bin/bash
echo "=== Exporting onboard_new_dispatcher result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Retrieve setup baselines
INITIAL_USER_COUNT=$(cat /tmp/initial_user_count 2>/dev/null || echo "0")
BASELINE_MAX_USER_ID=$(cat /tmp/baseline_max_user_id 2>/dev/null | tr -cd '0-9' || echo "0")
BASELINE_MAX_USER_ID=${BASELINE_MAX_USER_ID:-0}

# Query current state
CURRENT_USER_COUNT=$(get_user_count)

# Search for the target user "Elena Ross"
TARGET_EMAIL="elena.ross@opencad.local"

# Get User Details
# We select ID, Name, Email, Identifier, Approved status
USER_DATA=$(opencad_db_query "SELECT id, name, email, identifier, approved FROM users WHERE email='${TARGET_EMAIL}' LIMIT 1")

USER_FOUND="false"
USER_ID=""
USER_NAME=""
USER_EMAIL=""
USER_IDENTIFIER=""
USER_APPROVED=""
DEPT_ASSIGNED="false"
DEPT_NAME=""

if [ -n "$USER_DATA" ]; then
    USER_FOUND="true"
    USER_ID=$(echo "$USER_DATA" | cut -f1)
    USER_NAME=$(echo "$USER_DATA" | cut -f2)
    USER_EMAIL=$(echo "$USER_DATA" | cut -f3)
    USER_IDENTIFIER=$(echo "$USER_DATA" | cut -f4)
    USER_APPROVED=$(echo "$USER_DATA" | cut -f5)

    # Check Department Assignment (Communications usually ID 1)
    # Check both permanent table (user_departments) and temp table (user_departments_temp)
    # Correct state is in user_departments
    DEPT_CHECK=$(opencad_db_query "SELECT d.department_name FROM user_departments ud JOIN departments d ON ud.department_id = d.department_id WHERE ud.user_id = '${USER_ID}' AND d.department_name LIKE '%Communications%' LIMIT 1")
    
    if [ -n "$DEPT_CHECK" ]; then
        DEPT_ASSIGNED="true"
        DEPT_NAME="$DEPT_CHECK"
    else
        # Fallback check: see what departments ARE assigned
        DEPT_NAME=$(opencad_db_query "SELECT d.department_name FROM user_departments ud JOIN departments d ON ud.department_id = d.department_id WHERE ud.user_id = '${USER_ID}' LIMIT 1")
    fi
fi

# Check if user was created AFTER task start (ID > Baseline)
NEWLY_CREATED="false"
if [ "$USER_FOUND" = "true" ]; then
    if [ "$USER_ID" -gt "$BASELINE_MAX_USER_ID" ]; then
        NEWLY_CREATED="true"
    fi
fi

# Construct JSON result
RESULT_JSON=$(cat << EOF
{
    "initial_user_count": ${INITIAL_USER_COUNT},
    "current_user_count": ${CURRENT_USER_COUNT},
    "user_found": ${USER_FOUND},
    "newly_created": ${NEWLY_CREATED},
    "user": {
        "id": "$(json_escape "${USER_ID}")",
        "name": "$(json_escape "${USER_NAME}")",
        "email": "$(json_escape "${USER_EMAIL}")",
        "identifier": "$(json_escape "${USER_IDENTIFIER}")",
        "approved": "$(json_escape "${USER_APPROVED}")",
        "department_assigned": ${DEPT_ASSIGNED},
        "department_name": "$(json_escape "${DEPT_NAME}")"
    },
    "timestamp": "$(date -Iseconds)"
}
EOF
)

safe_write_result "$RESULT_JSON" /tmp/onboard_new_dispatcher_result.json

echo "Result saved to /tmp/onboard_new_dispatcher_result.json"
cat /tmp/onboard_new_dispatcher_result.json
echo "=== Export complete ==="