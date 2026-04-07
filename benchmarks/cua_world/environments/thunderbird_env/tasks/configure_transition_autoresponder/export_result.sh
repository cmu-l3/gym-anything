#!/bin/bash
echo "=== Exporting task results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Setup safe export directory
EXPORT_DIR="/tmp/task_exports"
rm -rf "$EXPORT_DIR"
mkdir -p "$EXPORT_DIR"
chmod 777 "$EXPORT_DIR"

# Find the Thunderbird profile directory
PROFILE_DIR=$(find /home/ga/.thunderbird -maxdepth 1 -type d -name "*default*" | head -n 1)

FILTER_MTIME=0
TEMPLATE_MTIME=0
FOLDER_EXISTS="false"

if [ -n "$PROFILE_DIR" ]; then
    # Export Filters
    if [ -f "$PROFILE_DIR/msgFilterRules.dat" ]; then
        cp "$PROFILE_DIR/msgFilterRules.dat" "$EXPORT_DIR/"
        chmod 666 "$EXPORT_DIR/msgFilterRules.dat"
        FILTER_MTIME=$(stat -c %Y "$PROFILE_DIR/msgFilterRules.dat" 2>/dev/null || echo "0")
    fi

    # Export Templates
    if [ -f "$PROFILE_DIR/Mail/Local Folders/Templates" ]; then
        cp "$PROFILE_DIR/Mail/Local Folders/Templates" "$EXPORT_DIR/"
        chmod 666 "$EXPORT_DIR/Templates"
        TEMPLATE_MTIME=$(stat -c %Y "$PROFILE_DIR/Mail/Local Folders/Templates" 2>/dev/null || echo "0")
    fi

    # Export Archive Folder (check existence)
    if [ -f "$PROFILE_DIR/Mail/Local Folders/MegaCorp Archive" ]; then
        cp "$PROFILE_DIR/Mail/Local Folders/MegaCorp Archive" "$EXPORT_DIR/"
        chmod 666 "$EXPORT_DIR/MegaCorp Archive"
        FOLDER_EXISTS="true"
    fi
fi

# Check if application was running
APP_RUNNING=$(pgrep -f "thunderbird" > /dev/null && echo "true" || echo "false")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_was_running": $APP_RUNNING,
    "folder_exists": $FOLDER_EXISTS,
    "filter_mtime": $FILTER_MTIME,
    "template_mtime": $TEMPLATE_MTIME
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Exported task state to /tmp/task_exports/ and /tmp/task_result.json"
echo "=== Export complete ==="