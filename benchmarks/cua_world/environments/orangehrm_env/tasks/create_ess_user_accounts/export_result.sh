#!/bin/bash
set -e
echo "=== Exporting task results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# ============================================================
# Gather Verification Data from Database
# ============================================================

# 1. Get current total user count
FINAL_USER_COUNT=$(orangehrm_count "ohrm_user" "1=1")

# 2. Get ESS Role ID (dynamic lookup)
ESS_ROLE_ID=$(orangehrm_db_query "SELECT id FROM ohrm_user_role WHERE name='ESS' LIMIT 1;" | tr -d '[:space:]')

# 3. Verify 'lisa.andrews'
LISA_EXISTS="false"
LISA_ROLE_ID=""
LISA_STATUS=""
LISA_LINKED_EMP=""

LISA_DATA=$(orangehrm_db_query "SELECT user_role_id, status, emp_number FROM ohrm_user WHERE user_name='lisa.andrews' LIMIT 1;")
if [ -n "$LISA_DATA" ]; then
    LISA_EXISTS="true"
    LISA_ROLE_ID=$(echo "$LISA_DATA" | awk '{print $1}')
    LISA_STATUS=$(echo "$LISA_DATA" | awk '{print $2}')
    LISA_LINKED_EMP=$(echo "$LISA_DATA" | awk '{print $3}')
fi

# 4. Verify 'david.morris'
DAVID_EXISTS="false"
DAVID_ROLE_ID=""
DAVID_STATUS=""
DAVID_LINKED_EMP=""

DAVID_DATA=$(orangehrm_db_query "SELECT user_role_id, status, emp_number FROM ohrm_user WHERE user_name='david.morris' LIMIT 1;")
if [ -n "$DAVID_DATA" ]; then
    DAVID_EXISTS="true"
    DAVID_ROLE_ID=$(echo "$DAVID_DATA" | awk '{print $1}')
    DAVID_STATUS=$(echo "$DAVID_DATA" | awk '{print $2}')
    DAVID_LINKED_EMP=$(echo "$DAVID_DATA" | awk '{print $3}')
fi

# 5. Load ground truth from setup
GROUND_TRUTH_FILE="/tmp/task_ground_truth.json"
INITIAL_USER_COUNT=0
LISA_TARGET_EMP=""
DAVID_TARGET_EMP=""

if [ -f "$GROUND_TRUTH_FILE" ]; then
    INITIAL_USER_COUNT=$(jq -r '.initial_user_count' "$GROUND_TRUTH_FILE")
    LISA_TARGET_EMP=$(jq -r '.lisa_emp_number' "$GROUND_TRUTH_FILE")
    DAVID_TARGET_EMP=$(jq -r '.david_emp_number' "$GROUND_TRUTH_FILE")
fi

# ============================================================
# Create JSON Result
# ============================================================
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "final_screenshot_path": "/tmp/task_final.png",
    "initial_user_count": $INITIAL_USER_COUNT,
    "final_user_count": $FINAL_USER_COUNT,
    "ess_role_id": "${ESS_ROLE_ID:-2}",
    "targets": {
        "lisa_emp_id": "${LISA_TARGET_EMP}",
        "david_emp_id": "${DAVID_TARGET_EMP}"
    },
    "users": {
        "lisa.andrews": {
            "exists": $LISA_EXISTS,
            "role_id": "${LISA_ROLE_ID}",
            "status": "${LISA_STATUS}",
            "linked_emp_number": "${LISA_LINKED_EMP}"
        },
        "david.morris": {
            "exists": $DAVID_EXISTS,
            "role_id": "${DAVID_ROLE_ID}",
            "status": "${DAVID_STATUS}",
            "linked_emp_number": "${DAVID_LINKED_EMP}"
        }
    }
}
EOF

# Move to final location with permission handling
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="