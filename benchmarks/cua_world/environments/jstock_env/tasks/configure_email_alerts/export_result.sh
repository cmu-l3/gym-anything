#!/bin/bash
echo "=== Exporting configure_email_alerts results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

JSTOCK_CONFIG_DIR="/home/ga/.jstock/1.0.7"

# Take final screenshot
DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority scrot /tmp/task_final.png 2>/dev/null || \
DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority import -window root /tmp/task_final.png 2>/dev/null || true

# Check if application is running
APP_RUNNING=$(pgrep -f "jstock.jar" > /dev/null && echo "true" || echo "false")

# ============================================================
# Search for configuration settings
# JStock stores settings in XML files or properties files.
# We will search recursively for the expected strings.
# ============================================================

CONFIG_FOUND="false"
SERVER_FOUND="false"
EMAIL_FOUND="false"
PORT_FOUND="false"
FILE_MODIFIED_DURING_TASK="false"
MATCHING_FILE=""

# Strings to search for
SEARCH_SERVER="smtp.gmail.com"
SEARCH_EMAIL="portfolio.alerts@gmail.com"
SEARCH_PORT="587"

# Find files modified after task start
# We look for files containing the server string first
echo "Searching for config files containing '$SEARCH_SERVER'..."
grep -r "$SEARCH_SERVER" "$JSTOCK_CONFIG_DIR" > /tmp/grep_results.txt || true

if [ -s /tmp/grep_results.txt ]; then
    echo "Found potential config files:"
    cat /tmp/grep_results.txt
    
    # Extract the first matching filename
    MATCHING_FILE=$(head -n 1 /tmp/grep_results.txt | cut -d: -f1)
    CONFIG_FOUND="true"
    
    # Check if this file was modified during the task
    FILE_MTIME=$(stat -c %Y "$MATCHING_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED_DURING_TASK="true"
    fi
    
    # Check for other values in the same file
    if grep -q "$SEARCH_SERVER" "$MATCHING_FILE"; then SERVER_FOUND="true"; fi
    if grep -q "$SEARCH_EMAIL" "$MATCHING_FILE"; then EMAIL_FOUND="true"; fi
    if grep -q "$SEARCH_PORT" "$MATCHING_FILE"; then PORT_FOUND="true"; fi
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_was_running": $APP_RUNNING,
    "config_found": $CONFIG_FOUND,
    "config_file_path": "$MATCHING_FILE",
    "file_modified_during_task": $FILE_MODIFIED_DURING_TASK,
    "settings_found": {
        "server": $SERVER_FOUND,
        "email": $EMAIL_FOUND,
        "port": $PORT_FOUND
    },
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location with permission handling
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="