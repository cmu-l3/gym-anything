#!/bin/bash
set -euo pipefail

echo "=== Exporting edit_cylinder_pressures result ==="

export DISPLAY="${DISPLAY:-:1}"

TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
SSRF_INITIAL_MTIME=$(cat /tmp/ssrf_initial_mtime.txt 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# Check log file modification
LOG_FILE="/home/ga/Documents/dives.ssrf"
LOG_EXISTS="false"
LOG_MODIFIED="false"
LOG_MTIME=0

if [ -f "$LOG_FILE" ]; then
    LOG_EXISTS="true"
    LOG_MTIME=$(stat -c%Y "$LOG_FILE" 2>/dev/null || echo "0")
    if [ "$LOG_MTIME" -gt "$SSRF_INITIAL_MTIME" ]; then
        LOG_MODIFIED="true"
    fi
fi

# Determine if Subsurface is still running
APP_RUNNING="false"
if pgrep -f "subsurface" > /dev/null; then
    APP_RUNNING="true"
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/task_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "log_exists": $LOG_EXISTS,
    "log_modified": $LOG_MODIFIED,
    "log_mtime": $LOG_MTIME,
    "initial_mtime": $SSRF_INITIAL_MTIME,
    "app_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="