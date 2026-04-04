#!/bin/bash
# export_result.sh - Capture results for visualize_flight_trends

echo "=== Exporting visualize_flight_trends result ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
SCRIPT_PATH="/home/ga/generate_chart.py"
IMAGE_PATH="/home/ga/flight_activity.png"

# 1. Take screenshot of the desktop/terminal state
DISPLAY=:1 scrot /tmp/final_state.png 2>/dev/null || true

# 2. Analyze the generated image
IMAGE_EXISTS="false"
IMAGE_SIZE="0"
IMAGE_CREATED_AFTER_START="false"

if [ -f "$IMAGE_PATH" ]; then
    IMAGE_EXISTS="true"
    IMAGE_SIZE=$(stat -c %s "$IMAGE_PATH" 2>/dev/null || echo "0")
    IMAGE_MTIME=$(stat -c %Y "$IMAGE_PATH" 2>/dev/null || echo "0")
    
    if [ "$IMAGE_MTIME" -gt "$TASK_START" ]; then
        IMAGE_CREATED_AFTER_START="true"
    fi
fi

# 3. Analyze the python script
SCRIPT_EXISTS="false"
SCRIPT_CONTENT=""
SCRIPT_IMPORTS_MATPLOTLIB="false"
SCRIPT_IMPORTS_FLIGHTPLAN="false"

if [ -f "$SCRIPT_PATH" ]; then
    SCRIPT_EXISTS="true"
    # Read script content (limit size just in case)
    SCRIPT_CONTENT=$(head -c 5000 "$SCRIPT_PATH" | base64 -w 0)
    
    if grep -q "matplotlib" "$SCRIPT_PATH"; then
        SCRIPT_IMPORTS_MATPLOTLIB="true"
    fi
    
    if grep -q "FlightPlan" "$SCRIPT_PATH"; then
        SCRIPT_IMPORTS_FLIGHTPLAN="true"
    fi
fi

# 4. Check if matplotlib is actually installed
MATPLOTLIB_INSTALLED=$(pip freeze | grep -i "matplotlib" > /dev/null && echo "true" || echo "false")

# 5. Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "image_exists": $IMAGE_EXISTS,
    "image_size_bytes": $IMAGE_SIZE,
    "image_created_during_task": $IMAGE_CREATED_AFTER_START,
    "script_exists": $SCRIPT_EXISTS,
    "script_imports_matplotlib": $SCRIPT_IMPORTS_MATPLOTLIB,
    "script_imports_flightplan": $SCRIPT_IMPORTS_FLIGHTPLAN,
    "matplotlib_installed": $MATPLOTLIB_INSTALLED,
    "script_content_b64": "$SCRIPT_CONTENT"
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"