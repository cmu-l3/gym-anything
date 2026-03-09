#!/bin/bash
echo "=== Exporting configure_profile_email results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Source utils for screenshot
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Check if application (Firefox) is still running
APP_RUNNING=$(pgrep -f "firefox" > /dev/null && echo "true" || echo "false")

# -----------------------------------------------------------------------------
# Check 1: Grep Firefox profile for the email string
# This verifies if the data was actually written to disk/local storage
# -----------------------------------------------------------------------------
FIREFOX_PROFILE_DIR="/home/ga/.mozilla/firefox/jitsi.profile"
EXPECTED_EMAIL="alex.manager@corp.global"
EMAIL_FOUND_ON_DISK="false"

echo "Searching for '$EXPECTED_EMAIL' in Firefox profile..."
# We use grep recursively. Binary match is likely in sqlite databases.
# We suppress output and just check exit code.
if grep -r -q "$EXPECTED_EMAIL" "$FIREFOX_PROFILE_DIR" 2>/dev/null; then
    EMAIL_FOUND_ON_DISK="true"
    echo "Email found in Firefox profile data."
else
    echo "Email NOT found in Firefox profile data."
fi

# -----------------------------------------------------------------------------
# Check 2: Check for user-created screenshots
# -----------------------------------------------------------------------------
USER_SCREENSHOT_EXISTS="false"
# Look for screenshots created after task start in typical locations
count=$(find /home/ga/ -name "*.png" -newermt "@$TASK_START" 2>/dev/null | wc -l)
if [ "$count" -gt 0 ]; then
    USER_SCREENSHOT_EXISTS="true"
fi

# -----------------------------------------------------------------------------
# Create Result JSON
# -----------------------------------------------------------------------------
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_running": $APP_RUNNING,
    "email_found_on_disk": $EMAIL_FOUND_ON_DISK,
    "user_screenshot_exists": $USER_SCREENSHOT_EXISTS,
    "final_screenshot_path": "/tmp/task_final.png",
    "expected_email": "$EXPECTED_EMAIL"
}
EOF

# Move to standard location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="