#!/bin/bash
echo "=== Exporting Secure Domain Auth Results ==="

# Source utilities
source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
ENV_FILE="/home/ga/jitsi/.env"
REPORT_FILE="/home/ga/jitsi/auth_config_report.txt"
RESULT_JSON="/tmp/task_result.json"

# 1. Take final screenshot (critical for VLM verification of login prompt)
take_screenshot /tmp/task_final.png

# 2. Check .env file configuration
echo "Checking .env configuration..."
ENABLE_AUTH_SET="false"
AUTH_TYPE_SET="false"
ENABLE_GUESTS_SET="false"
ENV_MODIFIED="false"

if [ -f "$ENV_FILE" ]; then
    # Check if file was modified after task start
    ENV_MTIME=$(stat -c %Y "$ENV_FILE" 2>/dev/null || echo "0")
    if [ "$ENV_MTIME" -gt "$TASK_START" ]; then
        ENV_MODIFIED="true"
    fi

    # Check variables (ignoring commented out lines)
    if grep -E "^ENABLE_AUTH=1" "$ENV_FILE" >/dev/null; then ENABLE_AUTH_SET="true"; fi
    if grep -E "^AUTH_TYPE=internal" "$ENV_FILE" >/dev/null; then AUTH_TYPE_SET="true"; fi
    if grep -E "^ENABLE_GUESTS=1" "$ENV_FILE" >/dev/null; then ENABLE_GUESTS_SET="true"; fi
fi

# 3. Check Docker Container Status & Restart
echo "Checking Docker containers..."
cd /home/ga/jitsi
# Get container IDs
PROSODY_ID=$(docker compose ps -q prosody)
JICOFO_ID=$(docker compose ps -q jicofo)
JVB_ID=$(docker compose ps -q jvb)
WEB_ID=$(docker compose ps -q web)

ALL_CONTAINERS_RUNNING="false"
CONTAINERS_RESTARTED="false"

if [ -n "$PROSODY_ID" ] && [ -n "$JICOFO_ID" ] && [ -n "$JVB_ID" ] && [ -n "$WEB_ID" ]; then
    # Check if they are actually running
    RUNNING_COUNT=$(docker inspect -f '{{.State.Running}}' "$PROSODY_ID" "$JICOFO_ID" "$JVB_ID" "$WEB_ID" | grep "true" | wc -l)
    if [ "$RUNNING_COUNT" -eq 4 ]; then
        ALL_CONTAINERS_RUNNING="true"
    fi
    
    # Check start time of Prosody container to verify restart occurred during task
    START_TS=$(docker inspect -f '{{.State.StartedAt}}' "$PROSODY_ID")
    # Convert ISO8601 to timestamp (using date parser)
    START_EPOCH=$(date -d "$START_TS" +%s 2>/dev/null || echo "0")
    
    if [ "$START_EPOCH" -gt "$TASK_START" ]; then
        CONTAINERS_RESTARTED="true"
    fi
fi

# 4. Check Prosody User Registration
echo "Checking Prosody user registration..."
USER_REGISTERED="false"
if [ -n "$PROSODY_ID" ]; then
    # Check if the user account file exists in the container
    # Path is typically /config/data/meet%2ejitsi/accounts/admin.dat
    if docker exec "$PROSODY_ID" sh -c "ls /config/data/meet%2ejitsi/accounts/admin.dat" >/dev/null 2>&1; then
        USER_REGISTERED="true"
    fi
fi

# 5. Check Report File
REPORT_EXISTS="false"
if [ -f "$REPORT_FILE" ]; then
    REPORT_EXISTS="true"
fi

# 6. Capture Firefox URL (to see if they are on the test page)
CURRENT_URL="unknown"
# Try to get URL from window title if possible, or assume based on last action
# Firefox window title format is usually "Page Title - Mozilla Firefox"
WIN_ID=$(DISPLAY=:1 xdotool search --class firefox | head -1)
if [ -n "$WIN_ID" ]; then
    WIN_TITLE=$(DISPLAY=:1 xdotool getwindowname "$WIN_ID")
    CURRENT_URL="$WIN_TITLE"
fi

# 7. Generate Result JSON
cat > "$RESULT_JSON" << EOF
{
    "env_modified_during_task": $ENV_MODIFIED,
    "enable_auth_set": $ENABLE_AUTH_SET,
    "auth_type_set": $AUTH_TYPE_SET,
    "enable_guests_set": $ENABLE_GUESTS_SET,
    "containers_running": $ALL_CONTAINERS_RUNNING,
    "containers_restarted": $CONTAINERS_RESTARTED,
    "prosody_user_registered": $USER_REGISTERED,
    "report_exists": $REPORT_EXISTS,
    "window_title": "$CURRENT_URL",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Set permissions
chmod 666 "$RESULT_JSON"

echo "Result saved to $RESULT_JSON"
cat "$RESULT_JSON"
echo "=== Export complete ==="