#!/bin/bash
echo "=== Exporting add_emg_widget results ==="

# Source utilities
if [ -f "/home/ga/openbci_task_utils.sh" ]; then
    source /home/ga/openbci_task_utils.sh
else
    take_screenshot() { DISPLAY=:1 scrot "$1" 2>/dev/null || true; }
fi

# 1. CAPTURE: Final screenshot for VLM verification
echo "Capturing final state..."
take_screenshot /tmp/task_final.png

# 2. CHECK: Process state
APP_RUNNING="false"
if pgrep -f "OpenBCI_GUI" > /dev/null; then
    APP_RUNNING="true"
fi

# 3. CHECK: Settings file (Best Effort)
# OpenBCI might save the layout to a JSON file in Settings. 
# We try to grep it for "EMG" as a secondary signal, though it may not be flushed to disk yet.
SETTINGS_FILE=$(find /home/ga/Documents/OpenBCI_GUI/Settings -name "*.json" -type f -print0 | xargs -0 ls -t | head -n 1 2>/dev/null || echo "")
EMG_IN_SETTINGS="false"
UV_LIMIT_IN_SETTINGS="false"

if [ -f "$SETTINGS_FILE" ]; then
    if grep -iq "EMG" "$SETTINGS_FILE"; then
        EMG_IN_SETTINGS="true"
    fi
    # Search for uV limit configuration if possible (heuristic)
    if grep -q "200" "$SETTINGS_FILE"; then
        UV_LIMIT_IN_SETTINGS="true"
    fi
fi

# 4. EXPORT: Create JSON result
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png",
    "settings_file_found": "$SETTINGS_FILE",
    "emg_in_settings_file": $EMG_IN_SETTINGS,
    "possible_uv_limit_in_file": $UV_LIMIT_IN_SETTINGS
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="