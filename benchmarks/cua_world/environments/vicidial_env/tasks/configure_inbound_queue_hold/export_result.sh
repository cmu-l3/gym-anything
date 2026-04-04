#!/bin/bash
set -e
echo "=== Exporting task results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Query the Vicidial Database for the 'SUPPORT' group
echo "Querying database for Inbound Group 'SUPPORT'..."

# We use a custom separator '|' to avoid issues with tabs or spaces in text fields
DB_RESULT=$(docker exec vicidial mysql -ucron -p1234 -D asterisk -N -e "SELECT active, group_name, group_color, periodic_announce_time, periodic_announce_filename, play_place_in_line, hold_time_option, hold_time_option_seconds, hold_time_option_exten, hold_time_option_press_filename FROM vicidial_inbound_groups WHERE group_id='SUPPORT';" 2>/dev/null | tr '\t' '|' || echo "")

# Parse result or set defaults if empty
if [ -n "$DB_RESULT" ]; then
    GROUP_EXISTS="true"
    # Read pipe-separated values
    IFS='|' read -r ACTIVE GROUP_NAME GROUP_COLOR PA_TIME PA_FILE PLACE_LINE HT_OPT HT_SEC HT_EXTEN HT_FILE <<< "$DB_RESULT"
else
    GROUP_EXISTS="false"
    ACTIVE=""
    GROUP_NAME=""
    GROUP_COLOR=""
    PA_TIME="0"
    PA_FILE=""
    PLACE_LINE=""
    HT_OPT=""
    HT_SEC="0"
    HT_EXTEN=""
    HT_FILE=""
fi

# Check if Firefox is still running
APP_RUNNING=$(pgrep -f "firefox" > /dev/null && echo "true" || echo "false")

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "group_exists": $GROUP_EXISTS,
    "data": {
        "active": "$ACTIVE",
        "group_name": "$GROUP_NAME",
        "group_color": "$GROUP_COLOR",
        "periodic_announce_time": "$PA_TIME",
        "periodic_announce_filename": "$PA_FILE",
        "play_place_in_line": "$PLACE_LINE",
        "hold_time_option": "$HT_OPT",
        "hold_time_option_seconds": "$HT_SEC",
        "hold_time_option_exten": "$HT_EXTEN",
        "hold_time_option_press_filename": "$HT_FILE"
    },
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location with permission handling
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
echo "=== Export complete ==="