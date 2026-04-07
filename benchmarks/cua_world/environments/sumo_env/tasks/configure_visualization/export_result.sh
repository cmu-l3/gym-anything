#!/bin/bash
echo "=== Exporting configure_visualization result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot of the environment
take_screenshot /tmp/task_final.png

# Read task start time
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 1. Check if congestion_map.png was created
SCREENSHOT_FILE="/home/ga/SUMO_Output/congestion_map.png"
SCREENSHOT_EXISTS="false"
SCREENSHOT_VALID="false"
SCREENSHOT_SIZE=0

if [ -f "$SCREENSHOT_FILE" ]; then
    SCREENSHOT_EXISTS="true"
    SCREENSHOT_SIZE=$(stat -c%s "$SCREENSHOT_FILE" 2>/dev/null || echo "0")
    SCREENSHOT_MTIME=$(stat -c%Y "$SCREENSHOT_FILE" 2>/dev/null || echo "0")
    
    # Check if it was created/modified during the task
    if [ "$SCREENSHOT_MTIME" -ge "$TASK_START" ]; then
        # Use basic file command to verify it's an image
        if file "$SCREENSHOT_FILE" | grep -qi "image data"; then
            SCREENSHOT_VALID="true"
        fi
    fi
fi

# 2. Check if visualization_settings.xml was exported
SETTINGS_FILE="/home/ga/SUMO_Output/visualization_settings.xml"
SETTINGS_EXISTS="false"
SETTINGS_HAS_SPEED="false"

if [ -f "$SETTINGS_FILE" ]; then
    SETTINGS_EXISTS="true"
    SETTINGS_MTIME=$(stat -c%Y "$SETTINGS_FILE" 2>/dev/null || echo "0")
    
    # Check if it was created/modified during the task and contains speed config
    if [ "$SETTINGS_MTIME" -ge "$TASK_START" ]; then
        if grep -qi "speed" "$SETTINGS_FILE"; then
            SETTINGS_HAS_SPEED="true"
        fi
    fi
fi

# 3. Check simulation progress from log
LOG_FILE="/home/ga/SUMO_Scenarios/bologna_pasubio/sumo_log.txt"
MAX_STEP=0
if [ -f "$LOG_FILE" ]; then
    # Extract the highest step number reached from lines like "Step #500.00"
    EXTRACTED_STEP=$(grep -oE "Step #[0-9]+" "$LOG_FILE" 2>/dev/null | grep -oE "[0-9]+" | sort -n | tail -1)
    if [ -n "$EXTRACTED_STEP" ]; then
        MAX_STEP=$EXTRACTED_STEP
    fi
fi

# 4. Check if SUMO is running
SUMO_RUNNING="false"
if is_sumo_gui_running; then
    SUMO_RUNNING="true"
fi

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "sumo_running": $SUMO_RUNNING,
    "screenshot_exists": $SCREENSHOT_EXISTS,
    "screenshot_valid": $SCREENSHOT_VALID,
    "screenshot_size_bytes": $SCREENSHOT_SIZE,
    "settings_exists": $SETTINGS_EXISTS,
    "settings_has_speed_coloring": $SETTINGS_HAS_SPEED,
    "max_simulation_step": $MAX_STEP,
    "final_desktop_screenshot": "/tmp/task_final.png"
}
EOF

rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json

echo "=== Export complete ==="