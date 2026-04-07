#!/bin/bash
# Export script for space_weather_dashboard_layout task

echo "=== Exporting space_weather_dashboard_layout result ==="

GPREDICT_CONF_DIR="/home/ga/.config/Gpredict"
GPREDICT_MOD_DIR="${GPREDICT_CONF_DIR}/modules"

# Record task end time
TASK_END_TIMESTAMP=$(date +%s)
TASK_START_TIMESTAMP=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot /tmp/task_end_screenshot.png 2>/dev/null || true

# Check if Space_Weather module exists (case-insensitive search)
MODULE_EXISTS="false"
MODULE_PATH=""
MODULE_CONTENT=""
MODULE_MTIME="0"

for mod in "${GPREDICT_MOD_DIR}"/*.mod; do
    [ -f "$mod" ] || continue
    modname=$(basename "$mod" .mod)
    if echo "$modname" | grep -qi "space.*weather"; then
        MODULE_EXISTS="true"
        MODULE_PATH="$mod"
        MODULE_MTIME=$(stat -c %Y "$mod" 2>/dev/null || echo "0")
        
        # Read the file content and escape it for JSON
        MODULE_CONTENT=$(cat "$mod" | tr '\n' '|' | sed 's/"/\\"/g; s/\\/\\\\/g')
        break
    fi
done

# Check if module was modified/created during the task
CREATED_DURING_TASK="false"
if [ "$MODULE_MTIME" -ge "$TASK_START_TIMESTAMP" ]; then
    CREATED_DURING_TASK="true"
fi

cat > /tmp/space_weather_result.json << EOF
{
    "task_start_time": $TASK_START_TIMESTAMP,
    "task_end_time": $TASK_END_TIMESTAMP,
    "module_exists": $MODULE_EXISTS,
    "module_created_during_task": $CREATED_DURING_TASK,
    "module_content": "$MODULE_CONTENT"
}
EOF

echo "Result saved to /tmp/space_weather_result.json"
cat /tmp/space_weather_result.json
echo ""
echo "=== Export Complete ==="