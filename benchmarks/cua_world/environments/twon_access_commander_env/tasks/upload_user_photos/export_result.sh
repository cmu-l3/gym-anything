#!/bin/bash
echo "=== Exporting upload_user_photos task result ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_USER_COUNT=$(cat /tmp/initial_user_count.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Authenticate with API to check user states
ac_login > /dev/null 2>&1

# Get all users
USERS_JSON=$(ac_api GET "/users" 2>/dev/null)
FINAL_USER_COUNT=$(echo "$USERS_JSON" | jq length 2>/dev/null || echo "0")

# Helper function to check if a user has an image attached
check_user_image() {
    local first=$1
    local last=$2
    local uid=$(echo "$USERS_JSON" | jq -r ".[] | select(.firstName==\"$first\" and .lastName==\"$last\") | .id" 2>/dev/null)
    
    if [ -n "$uid" ] && [ "$uid" != "null" ]; then
        # Check image existence via HTTP status code (200 OK vs 404 Not Found)
        local http_code=$(curl -sk -b "$COOKIE_JAR" -o /dev/null -w "%{http_code}" "${AC_URL}/api/v3/users/${uid}/image")
        if [ "$http_code" = "200" ]; then
            echo "true"
        else
            echo "false"
        fi
    else
        echo "not_found"
    fi
}

# Check our targets
VICTOR_HAS_IMAGE=$(check_user_image "Victor" "Schulz")
TAMARA_HAS_IMAGE=$(check_user_image "Tamara" "Kowalski")
LEON_HAS_IMAGE=$(check_user_image "Leon" "Fischer")

# Check if app is still running
APP_RUNNING=$(pgrep -f "firefox" > /dev/null && echo "true" || echo "false")

# Save results to JSON safely
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_was_running": $APP_RUNNING,
    "initial_user_count": $INITIAL_USER_COUNT,
    "final_user_count": $FINAL_USER_COUNT,
    "targets": {
        "victor_schulz_has_image": $VICTOR_HAS_IMAGE,
        "tamara_kowalski_has_image": $TAMARA_HAS_IMAGE,
        "leon_fischer_has_image": $LEON_HAS_IMAGE
    }
}
EOF

# Move to final location with permissive permissions
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json

echo "=== Export complete ==="