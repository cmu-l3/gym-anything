#!/bin/bash
echo "=== Exporting role_access_reconfiguration result ==="

source /workspace/scripts/task_utils.sh

# Record end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# --- Queries to extract the agent's work ---

# 1. Check if roles were created
TL_COUNT=$(sentrifugo_db_query "SELECT COUNT(*) FROM main_roles WHERE rolename='Team Lead' AND isactive=1;" | tr -d '[:space:]')
FC_COUNT=$(sentrifugo_db_query "SELECT COUNT(*) FROM main_roles WHERE rolename='Finance Clerk' AND isactive=1;" | tr -d '[:space:]')
PC_COUNT=$(sentrifugo_db_query "SELECT COUNT(*) FROM main_roles WHERE rolename='Program Coordinator' AND isactive=1;" | tr -d '[:space:]')

# 2. Check employee assignments
get_emp_role() {
    local emp="$1"
    # Try role_id column
    local role=$(sentrifugo_db_query "SELECT r.rolename FROM main_users u JOIN main_roles r ON u.role_id = r.id WHERE u.employeeId='$emp' LIMIT 1;" 2>/dev/null | tr -d '\r\n')
    # If empty, try userrole column
    if [ -z "$role" ] || [ "$role" = "NULL" ]; then
        role=$(sentrifugo_db_query "SELECT r.rolename FROM main_users u JOIN main_roles r ON u.userrole = r.id WHERE u.employeeId='$emp' LIMIT 1;" 2>/dev/null | tr -d '\r\n')
    fi
    echo "$role"
}

ROLE_EMP005=$(get_emp_role "EMP005")
ROLE_EMP009=$(get_emp_role "EMP009")
ROLE_EMP014=$(get_emp_role "EMP014")
ROLE_EMP017=$(get_emp_role "EMP017")

# Create JSON report securely
TEMP_JSON=$(mktemp /tmp/role_access_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "roles_created": {
        "Team Lead": $(if [ "${TL_COUNT:-0}" -gt 0 ]; then echo "true"; else echo "false"; fi),
        "Finance Clerk": $(if [ "${FC_COUNT:-0}" -gt 0 ]; then echo "true"; else echo "false"; fi),
        "Program Coordinator": $(if [ "${PC_COUNT:-0}" -gt 0 ]; then echo "true"; else echo "false"; fi)
    },
    "employee_roles": {
        "EMP005": "${ROLE_EMP005:-Unknown}",
        "EMP009": "${ROLE_EMP009:-Unknown}",
        "EMP014": "${ROLE_EMP014:-Unknown}",
        "EMP017": "${ROLE_EMP017:-Unknown}"
    }
}
EOF

# Move to final location and correct permissions
rm -f /tmp/role_access_result.json 2>/dev/null || sudo rm -f /tmp/role_access_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/role_access_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/role_access_result.json
chmod 666 /tmp/role_access_result.json 2>/dev/null || sudo chmod 666 /tmp/role_access_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result JSON saved to /tmp/role_access_result.json"
cat /tmp/role_access_result.json

echo "=== Export Complete ==="