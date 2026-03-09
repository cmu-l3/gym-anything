#!/bin/bash
echo "=== Exporting customize_watchlist_columns results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot (Critical for VLM verification)
echo "Capturing final state..."
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# Check if JStock is running
APP_RUNNING=$(pgrep -f "jstock.jar" > /dev/null && echo "true" || echo "false")

# Gracefully close JStock to force it to flush settings to disk
# (JStock often saves preferences only on exit)
if [ "$APP_RUNNING" = "true" ]; then
    echo "Attempting to close JStock gracefully to save settings..."
    DISPLAY=:1 wmctrl -r "JStock" -c 2>/dev/null || true
    # Wait for process to exit
    for i in {1..10}; do
        if ! pgrep -f "jstock.jar" > /dev/null; then
            break
        fi
        sleep 1
    done
fi

# Check for config file modification
# JStock 1.0.7 typically stores config in ~/.jstock/1.0.7/jstock.xml or options.xml
CONFIG_DIR="/home/ga/.jstock/1.0.7"
CONFIG_MODIFIED="false"
LATEST_CONFIG_FILE=""

# Find the most recently modified XML file in the config dir
if [ -d "$CONFIG_DIR" ]; then
    LATEST_XML=$(find "$CONFIG_DIR" -maxdepth 1 -name "*.xml" -printf "%T@ %p\n" 2>/dev/null | sort -n | tail -1 | cut -d' ' -f2-)
    
    if [ -f "$LATEST_XML" ]; then
        LATEST_CONFIG_FILE="$LATEST_XML"
        FILE_MTIME=$(stat -c %Y "$LATEST_XML" 2>/dev/null || echo "0")
        
        if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
            CONFIG_MODIFIED="true"
            echo "Config file modified during task: $LATEST_XML"
        fi
    fi
fi

# Copy relevant config file to tmp for the verifier to potentially inspect
if [ -n "$LATEST_CONFIG_FILE" ]; then
    cp "$LATEST_CONFIG_FILE" /tmp/jstock_config_snapshot.xml
    chmod 666 /tmp/jstock_config_snapshot.xml
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_was_running": $APP_RUNNING,
    "config_modified": $CONFIG_MODIFIED,
    "config_file": "$LATEST_CONFIG_FILE",
    "screenshot_path": "/tmp/task_final.png",
    "config_snapshot_path": "/tmp/jstock_config_snapshot.xml"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="