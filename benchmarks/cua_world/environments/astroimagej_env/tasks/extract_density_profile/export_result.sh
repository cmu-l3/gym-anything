#!/bin/bash
set -e

echo "=== Exporting extract_density_profile results ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

PROFILE_PATH="/home/ga/AstroImages/measurements/profile.txt"
REPORT_PATH="/home/ga/AstroImages/measurements/core_report.json"

# Capture final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Check profile.txt
PROFILE_EXISTS="false"
PROFILE_CREATED_DURING_TASK="false"
if [ -f "$PROFILE_PATH" ]; then
    PROFILE_EXISTS="true"
    PROFILE_MTIME=$(stat -c %Y "$PROFILE_PATH" 2>/dev/null || echo "0")
    if [ "$PROFILE_MTIME" -gt "$TASK_START" ]; then
        PROFILE_CREATED_DURING_TASK="true"
    fi
    # Copy to /tmp for easy verifier access
    cp "$PROFILE_PATH" /tmp/agent_profile.txt
    chmod 666 /tmp/agent_profile.txt
fi

# Check core_report.json
REPORT_EXISTS="false"
REPORT_CREATED_DURING_TASK="false"
if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_MTIME=$(stat -c %Y "$REPORT_PATH" 2>/dev/null || echo "0")
    if [ "$REPORT_MTIME" -gt "$TASK_START" ]; then
        REPORT_CREATED_DURING_TASK="true"
    fi
    # Copy to /tmp for easy verifier access
    cp "$REPORT_PATH" /tmp/agent_core_report.json
    chmod 666 /tmp/agent_core_report.json
fi

# Determine if app is running
APP_RUNNING=$(pgrep -f "astroimagej\|AstroImageJ\|aij" > /dev/null && echo "true" || echo "false")

# Assemble JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "profile_exists": $PROFILE_EXISTS,
    "profile_created_during_task": $PROFILE_CREATED_DURING_TASK,
    "report_exists": $REPORT_EXISTS,
    "report_created_during_task": $REPORT_CREATED_DURING_TASK,
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result metadata saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="