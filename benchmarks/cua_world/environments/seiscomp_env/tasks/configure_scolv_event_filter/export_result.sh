#!/bin/bash
echo "=== Exporting configure_scolv_event_filter results ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Check if scolv is running
SCOLV_RUNNING="false"
if pgrep -f "seiscomp/bin/scolv" > /dev/null; then
    SCOLV_RUNNING="true"
fi

# Export configuration files
# The agent could edit either the user config or global scolv config
USER_CONFIG="/home/ga/.seiscomp/scolv.cfg"
GLOBAL_CONFIG="/home/ga/seiscomp/etc/scolv.cfg"
EXPORTED_CONFIG="/tmp/exported_scolv.cfg"

rm -f "$EXPORTED_CONFIG"
touch "$EXPORTED_CONFIG"

CONFIG_MODIFIED="false"

if [ -f "$USER_CONFIG" ]; then
    echo "=== USER CONFIG ($USER_CONFIG) ===" >> "$EXPORTED_CONFIG"
    cat "$USER_CONFIG" >> "$EXPORTED_CONFIG"
    echo "" >> "$EXPORTED_CONFIG"
    
    MTIME=$(stat -c %Y "$USER_CONFIG" 2>/dev/null || echo "0")
    if [ "$MTIME" -ge "$TASK_START" ]; then
        CONFIG_MODIFIED="true"
    fi
fi

if [ -f "$GLOBAL_CONFIG" ]; then
    echo "=== GLOBAL CONFIG ($GLOBAL_CONFIG) ===" >> "$EXPORTED_CONFIG"
    cat "$GLOBAL_CONFIG" >> "$EXPORTED_CONFIG"
    echo "" >> "$EXPORTED_CONFIG"
    
    MTIME=$(stat -c %Y "$GLOBAL_CONFIG" 2>/dev/null || echo "0")
    if [ "$MTIME" -ge "$TASK_START" ]; then
        CONFIG_MODIFIED="true"
    fi
fi

chmod 644 "$EXPORTED_CONFIG"

# Build JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "scolv_running": $SCOLV_RUNNING,
    "config_modified_during_task": $CONFIG_MODIFIED,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="