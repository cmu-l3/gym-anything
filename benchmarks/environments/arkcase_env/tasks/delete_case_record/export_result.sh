#!/bin/bash
# Export script for delete_case_record task
# Checks if the target case is gone and the control case still exists

echo "=== Exporting delete_case_record result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Retrieve stored IDs
TARGET_ID=$(cat /tmp/target_case_id.txt 2>/dev/null || echo "")
CONTROL_ID=$(cat /tmp/control_case_id.txt 2>/dev/null || echo "")

if [ -z "$TARGET_ID" ]; then
    echo "CRITICAL ERROR: Target ID was not recorded during setup."
    TARGET_GONE="false" # Fail safe
else
    # Check Target Case Status
    echo "Checking status of Target Case ($TARGET_ID)..."
    # Note: arkcase_api function uses curl -f implicitly if configured, but let's check http code
    # We use a direct curl here to capture HTTP status code specifically for 404 check
    HTTP_CODE_TARGET=$(curl -sk -o /dev/null -w "%{http_code}" -u "${ARKCASE_ADMIN}:${ARKCASE_PASS}" "${ARKCASE_URL}/api/v1/plugin/complaint/${TARGET_ID}")
    
    echo "Target Case HTTP Status: $HTTP_CODE_TARGET"
    
    if [ "$HTTP_CODE_TARGET" = "404" ]; then
        TARGET_GONE="true"
    elif [ "$HTTP_CODE_TARGET" = "200" ]; then
        # If it returns 200, check if status is "DELETED" (soft delete) if ArkCase supports that
        # Otherwise, if it's found, it's not deleted.
        TARGET_GONE="false"
    else
        # 500 or other error
        TARGET_GONE="false"
    fi
fi

if [ -z "$CONTROL_ID" ]; then
    echo "WARNING: Control ID not found."
    CONTROL_EXISTS="true" # Benefit of the doubt if setup failed
else
    # Check Control Case Status
    echo "Checking status of Control Case ($CONTROL_ID)..."
    HTTP_CODE_CONTROL=$(curl -sk -o /dev/null -w "%{http_code}" -u "${ARKCASE_ADMIN}:${ARKCASE_PASS}" "${ARKCASE_URL}/api/v1/plugin/complaint/${CONTROL_ID}")
    
    echo "Control Case HTTP Status: $HTTP_CODE_CONTROL"
    
    if [ "$HTTP_CODE_CONTROL" = "200" ]; then
        CONTROL_EXISTS="true"
    else
        CONTROL_EXISTS="false"
    fi
fi

# Determine if App (Firefox) is still running
APP_RUNNING=$(pgrep -f firefox > /dev/null && echo "true" || echo "false")

# Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "target_case_id": "$TARGET_ID",
    "target_case_gone": $TARGET_GONE,
    "control_case_id": "$CONTROL_ID",
    "control_case_exists": $CONTROL_EXISTS,
    "app_running": $APP_RUNNING,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to standard location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="