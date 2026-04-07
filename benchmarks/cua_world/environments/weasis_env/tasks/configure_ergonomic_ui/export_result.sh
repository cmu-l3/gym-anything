#!/bin/bash
echo "=== Exporting configure_ergonomic_ui task result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
EXPORT_DIR="/home/ga/DICOM/exports"

SCREENSHOT_EXISTS="false"
SCREENSHOT_CREATED="false"
SCREENSHOT_SIZE=0
if [ -f "$EXPORT_DIR/ergonomic_ui.png" ]; then
    SCREENSHOT_EXISTS="true"
    SCREENSHOT_SIZE=$(stat -c %s "$EXPORT_DIR/ergonomic_ui.png" 2>/dev/null || echo "0")
    MTIME=$(stat -c %Y "$EXPORT_DIR/ergonomic_ui.png" 2>/dev/null || echo "0")
    if [ "$MTIME" -gt "$TASK_START" ]; then
        SCREENSHOT_CREATED="true"
    fi
fi

REPORT_EXISTS="false"
REPORT_CREATED="false"
REPORT_CONTENT=""
if [ -f "$EXPORT_DIR/ui_settings.txt" ]; then
    REPORT_EXISTS="true"
    # Safely read and escape text file
    REPORT_CONTENT=$(cat "$EXPORT_DIR/ui_settings.txt" | head -n 10 | tr '\n' ' ' | sed 's/"/\\"/g' | sed "s/'/\\\\'/g")
    MTIME=$(stat -c %Y "$EXPORT_DIR/ui_settings.txt" 2>/dev/null || echo "0")
    if [ "$MTIME" -gt "$TASK_START" ]; then
        REPORT_CREATED="true"
    fi
fi

APP_RUNNING="false"
if pgrep -f weasis > /dev/null; then
    APP_RUNNING="true"
fi

# Extract preferences saved to disk (agent actions may update this)
PREFS_THEME=""
PREFS_FONT=""

WEASIS_PREFS="/home/ga/.weasis/weasis.properties"
SNAP_PREFS="/home/ga/snap/weasis/current/.weasis/weasis.properties"

if [ -f "$SNAP_PREFS" ]; then
    PREFS_THEME=$(grep -i "weasis.look=" "$SNAP_PREFS" | cut -d'=' -f2 | tr -d '\r' || echo "")
    PREFS_FONT=$(grep -i "weasis.font.size=" "$SNAP_PREFS" | cut -d'=' -f2 | tr -d '\r' || echo "")
elif [ -f "$WEASIS_PREFS" ]; then
    PREFS_THEME=$(grep -i "weasis.look=" "$WEASIS_PREFS" | cut -d'=' -f2 | tr -d '\r' || echo "")
    PREFS_FONT=$(grep -i "weasis.font.size=" "$WEASIS_PREFS" | cut -d'=' -f2 | tr -d '\r' || echo "")
fi

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "screenshot_exists": $SCREENSHOT_EXISTS,
    "screenshot_created_during_task": $SCREENSHOT_CREATED,
    "screenshot_size": $SCREENSHOT_SIZE,
    "report_exists": $REPORT_EXISTS,
    "report_created_during_task": $REPORT_CREATED,
    "report_content": "$REPORT_CONTENT",
    "app_running": $APP_RUNNING,
    "prefs_theme": "$PREFS_THEME",
    "prefs_font": "$PREFS_FONT",
    "timestamp": "$(date -Iseconds)"
}
EOF

rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="