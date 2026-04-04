#!/bin/bash
echo "=== Exporting configure_service_watchdog result ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
STATUS_DIR="/etc/webmin/status"
CONFIG_FILE="$STATUS_DIR/config"

# Capture final screenshot
take_screenshot /tmp/task_final.png

# --- Parse Main Configuration (Scheduling) ---
SCHED_MODE="0"
SCHED_INT="0"
CONFIG_MTIME="0"

if [ -f "$CONFIG_FILE" ]; then
    SCHED_MODE=$(grep "^sched_mode=" "$CONFIG_FILE" | cut -d= -f2 | tr -d '\r')
    SCHED_INT=$(grep "^sched_int=" "$CONFIG_FILE" | cut -d= -f2 | tr -d '\r')
    CONFIG_MTIME=$(stat -c %Y "$CONFIG_FILE" 2>/dev/null || echo "0")
fi

# --- Find and Parse MySQL Monitor ---
MONITOR_FOUND="false"
MONITOR_CMD=""
MONITOR_DESC=""
MONITOR_MTIME="0"
MONITOR_FILE=""

# Webmin stores monitors in *.serv files. We need to find the one for MySQL.
# Iterate through all .serv files
for f in "$STATUS_DIR"/*.serv; do
    [ -e "$f" ] || continue
    if grep -q "^type=mysql" "$f"; then
        MONITOR_FOUND="true"
        MONITOR_FILE="$f"
        # Extract fields
        MONITOR_CMD=$(grep "^cmd=" "$f" | cut -d= -f2- | tr -d '\r')
        MONITOR_DESC=$(grep "^desc=" "$f" | cut -d= -f2- | tr -d '\r')
        MONITOR_MTIME=$(stat -c %Y "$f" 2>/dev/null || echo "0")
        break 
    fi
done

# --- JSON Export ---
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $TASK_START,
    "config_exists": $([ -f "$CONFIG_FILE" ] && echo "true" || echo "false"),
    "sched_mode": "${SCHED_MODE:-0}",
    "sched_int": "${SCHED_INT:-0}",
    "config_mtime": $CONFIG_MTIME,
    "monitor_found": $MONITOR_FOUND,
    "monitor_cmd": "$(json_escape "$MONITOR_CMD")",
    "monitor_desc": "$(json_escape "$MONITOR_DESC")",
    "monitor_mtime": $MONITOR_MTIME,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location
chmod 644 "$TEMP_JSON"
mv "$TEMP_JSON" /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="