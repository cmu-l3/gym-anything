#!/bin/bash
echo "=== Exporting Create User Role Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# 1. Check if Role exists in Database
# We select the role and description
ROLE_DATA=$(omrs_db_query "SELECT role, description FROM role WHERE role = 'Safety Auditor'")

ROLE_EXISTS="false"
ROLE_NAME=""
ROLE_DESC=""

if [ -n "$ROLE_DATA" ]; then
    ROLE_EXISTS="true"
    # Parse tab-separated output
    ROLE_NAME=$(echo "$ROLE_DATA" | awk -F'\t' '{print $1}')
    ROLE_DESC=$(echo "$ROLE_DATA" | awk -F'\t' '{print $2}')
fi

# 2. Get Assigned Privileges from Database
# We want a clean list of privileges for this role
PRIVILEGES_DATA=$(omrs_db_query "SELECT privilege FROM role_privilege WHERE role = 'Safety Auditor' ORDER BY privilege ASC")

# Convert newline-separated privileges to a JSON array string
# e.g. "View Encounters\nView Patients" -> ["View Encounters", "View Patients"]
PRIVILEGES_JSON="[]"
if [ -n "$PRIVILEGES_DATA" ]; then
    PRIVILEGES_JSON=$(echo "$PRIVILEGES_DATA" | python3 -c 'import sys, json; print(json.dumps([line.strip() for line in sys.stdin if line.strip()]))')
fi

# 3. Check for any inherited roles (should be none)
INHERITED_ROLES_COUNT=$(omrs_db_query "SELECT COUNT(*) FROM role_role WHERE child_role = 'Safety Auditor'")
if [ -z "$INHERITED_ROLES_COUNT" ]; then INHERITED_ROLES_COUNT="0"; fi

# 4. Check if App is running
APP_RUNNING=$(pgrep -f firefox > /dev/null && echo "true" || echo "false")

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "role_exists": $ROLE_EXISTS,
    "role_name": "$ROLE_NAME",
    "role_description": "$ROLE_DESC",
    "privileges": $PRIVILEGES_JSON,
    "inherited_roles_count": $INHERITED_ROLES_COUNT,
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location with safe permissions
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="