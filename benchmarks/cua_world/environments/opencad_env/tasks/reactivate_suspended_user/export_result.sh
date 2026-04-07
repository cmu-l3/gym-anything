#!/bin/bash
echo "=== Exporting reactivate_suspended_user task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot for evidence
take_screenshot /tmp/task_final_state.png

# Query current states
JAMES_NOW=$(opencad_db_query "SELECT approved FROM users WHERE email = 'james.rodriguez@opencad.local'")
ADMIN_NOW=$(opencad_db_query "SELECT approved FROM users WHERE email = 'admin@opencad.local'")
DISPATCH_NOW=$(opencad_db_query "SELECT approved FROM users WHERE email = 'dispatch@opencad.local'")
SARAH_NOW=$(opencad_db_query "SELECT approved FROM users WHERE email = 'sarah.mitchell@opencad.local'")

# Get initial states
JAMES_INITIAL=$(cat /tmp/james_initial_approved.txt 2>/dev/null || echo "0")
ADMIN_INITIAL=$(cat /tmp/admin_initial_approved.txt 2>/dev/null || echo "1")
DISPATCH_INITIAL=$(cat /tmp/dispatch_initial_approved.txt 2>/dev/null || echo "1")
SARAH_INITIAL=$(cat /tmp/sarah_initial_approved.txt 2>/dev/null || echo "0")

# Check if application was running (simple check)
APP_RUNNING="false"
if pgrep -f firefox > /dev/null; then
    APP_RUNNING="true"
fi

# Create JSON result
# Note: json_escape isn't strictly necessary for simple integers but good practice for robust scripts
RESULT_JSON=$(cat <<EOF
{
    "james_initial": "$(echo $JAMES_INITIAL | tr -d '[:space:]')",
    "james_now": "$(echo $JAMES_NOW | tr -d '[:space:]')",
    "admin_initial": "$(echo $ADMIN_INITIAL | tr -d '[:space:]')",
    "admin_now": "$(echo $ADMIN_NOW | tr -d '[:space:]')",
    "dispatch_initial": "$(echo $DISPATCH_INITIAL | tr -d '[:space:]')",
    "dispatch_now": "$(echo $DISPATCH_NOW | tr -d '[:space:]')",
    "sarah_initial": "$(echo $SARAH_INITIAL | tr -d '[:space:]')",
    "sarah_now": "$(echo $SARAH_NOW | tr -d '[:space:]')",
    "app_running": $APP_RUNNING,
    "timestamp": "$(date -Iseconds)"
}
EOF
)

safe_write_result "$RESULT_JSON" /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="