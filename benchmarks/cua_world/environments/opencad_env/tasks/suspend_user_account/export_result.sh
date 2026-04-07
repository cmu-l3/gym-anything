#!/bin/bash
echo "=== Exporting suspend_user_account result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot for visual verification
take_screenshot /tmp/task_final.png

# Get Task Timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
CURRENT_TIME=$(date +%s)

# 1. Check James Rodriguez's final state
# We check 'approved' status and 'suspend_reason'
# In standard OpenCAD: approved=1 is active, approved=2 is suspended, approved=0 is pending
JAMES_DATA=$(opencad_db_query "SELECT id, name, approved, suspend_reason FROM users WHERE email='james.rodriguez@opencad.local'")

JAMES_ID=""
JAMES_NAME=""
JAMES_APPROVED=""
JAMES_REASON=""
JAMES_FOUND="false"

if [ -n "$JAMES_DATA" ]; then
    JAMES_FOUND="true"
    JAMES_ID=$(echo "$JAMES_DATA" | cut -f1)
    JAMES_NAME=$(echo "$JAMES_DATA" | cut -f2)
    JAMES_APPROVED=$(echo "$JAMES_DATA" | cut -f3)
    JAMES_REASON=$(echo "$JAMES_DATA" | cut -f4)
fi

# 2. Check Admin User state (Collateral damage check)
ADMIN_APPROVED=$(opencad_db_query "SELECT approved FROM users WHERE email='admin@opencad.local'")

# 3. Check for specific anti-gaming timestamps (if DB tracks updated_at)
# OpenCAD 'users' table might not have updated_at by default, relying on state change check vs initial

# Construct JSON result
# Note: json_escape function is defined in task_utils.sh
RESULT_JSON=$(cat << EOF
{
    "task_start_timestamp": $TASK_START,
    "export_timestamp": $CURRENT_TIME,
    "james_rodriguez": {
        "found": $JAMES_FOUND,
        "id": "$(json_escape "${JAMES_ID}")",
        "name": "$(json_escape "${JAMES_NAME}")",
        "approved_status": "$(json_escape "${JAMES_APPROVED}")",
        "suspend_reason": "$(json_escape "${JAMES_REASON}")"
    },
    "admin_user": {
        "approved_status": "$(json_escape "${ADMIN_APPROVED}")"
    },
    "initial_status": "$(cat /tmp/initial_james_status.txt 2>/dev/null | tr -d '\n')"
}
EOF
)

# Save result with permissions
safe_write_result "$RESULT_JSON" /tmp/suspend_user_result.json

echo "Result saved to /tmp/suspend_user_result.json"
cat /tmp/suspend_user_result.json
echo "=== Export complete ==="