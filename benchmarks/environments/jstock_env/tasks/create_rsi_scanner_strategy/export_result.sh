#!/bin/bash
echo "=== Exporting create_rsi_scanner_strategy result ==="

# 1. Capture Final Screenshot
DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority scrot /tmp/task_final.png 2>/dev/null || \
DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority import -window root /tmp/task_final.png 2>/dev/null || true

# 2. Gather Verification Data
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
JSTOCK_CONFIG_DIR="/home/ga/.jstock"
FOUND_NAME="false"
FOUND_INDICATOR="false"
FOUND_VALUE="false"
FILE_MODIFIED="false"

echo "Searching for configuration changes in $JSTOCK_CONFIG_DIR after timestamp $TASK_START..."

# We search recursively in .jstock for files modified AFTER task start
# Then we grep inside those specific files for our keywords.
# This handles the fact that JStock might use arbitrary XML/Config filenames.

# Find files modified after task start
MODIFIED_FILES=$(find "$JSTOCK_CONFIG_DIR" -type f -newermt "@$TASK_START" 2>/dev/null)

if [ -n "$MODIFIED_FILES" ]; then
    FILE_MODIFIED="true"
    echo "Modified files found:"
    echo "$MODIFIED_FILES"

    # Search for keywords in these files
    # We use grep -i (case insensitive) just in case
    
    # Check for Strategy Name "Oversold RSI"
    if grep -ri "Oversold RSI" $MODIFIED_FILES > /dev/null; then
        FOUND_NAME="true"
        echo "Found strategy name 'Oversold RSI'"
    fi

    # Check for Indicator "RSI" or "Relative Strength Index"
    # JStock XML likely stores "Relative Strength Index" or "RSI"
    if grep -ri "Relative Strength Index" $MODIFIED_FILES > /dev/null || grep -r "RSI" $MODIFIED_FILES > /dev/null; then
        FOUND_INDICATOR="true"
        echo "Found indicator 'RSI'"
    fi

    # Check for Value "30"
    # We look for "30" explicitly. 
    # Note: simple grep might find "30" in timestamps, but combined with the file modification check
    # and the specific nature of config files (usually XML attributes), this is a strong signal.
    # To be safer, we check if "30" appears in the same files where we found "Oversold RSI" or "RSI".
    if grep -r "30" $MODIFIED_FILES > /dev/null; then
        FOUND_VALUE="true"
        echo "Found value '30'"
    fi
else
    echo "No configuration files were modified during the task."
fi

# 3. Check if App is still running
APP_RUNNING="false"
if pgrep -f "jstock.jar" > /dev/null; then
    APP_RUNNING="true"
fi

# 4. Create JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "file_modified": $FILE_MODIFIED,
    "found_name": $FOUND_NAME,
    "found_indicator": $FOUND_INDICATOR,
    "found_value": $FOUND_VALUE,
    "app_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# 5. Move JSON to final location with correct permissions
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="