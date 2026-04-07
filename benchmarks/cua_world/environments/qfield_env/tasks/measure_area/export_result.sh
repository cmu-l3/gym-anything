#!/system/bin/sh
# Export script for measure_area task
# Runs inside Android emulator

echo "=== Exporting measure_area results ==="

PACKAGE="ch.opengis.qfield"
RESULT_FILE="/sdcard/task_result.json"

# 1. Capture Final Screenshot (Critical for VLM)
screencap -p /sdcard/task_final.png 2>/dev/null || true

# 2. Gather Task Metrics
# Check if app is still running
if pidof "$PACKAGE" > /dev/null; then
    APP_RUNNING="true"
else
    APP_RUNNING="false"
fi

# Get timing
START_TIME=$(cat /sdcard/task_start_time.txt 2>/dev/null || echo "0")
END_TIME=$(date +%s)

# Check for screenshots existence
if [ -f "/sdcard/task_final.png" ]; then
    SCREENSHOT_EXISTS="true"
else
    SCREENSHOT_EXISTS="false"
fi

# 3. Create Result JSON
# Android shell has limited JSON tools, constructing string manually
echo "{" > "$RESULT_FILE"
echo "  \"app_running\": $APP_RUNNING," >> "$RESULT_FILE"
echo "  \"start_time\": $START_TIME," >> "$RESULT_FILE"
echo "  \"end_time\": $END_TIME," >> "$RESULT_FILE"
echo "  \"screenshot_path\": \"/sdcard/task_final.png\"," >> "$RESULT_FILE"
echo "  \"screenshot_exists\": $SCREENSHOT_EXISTS" >> "$RESULT_FILE"
echo "}" >> "$RESULT_FILE"

# Output for logging
cat "$RESULT_FILE"

echo "=== Export complete ==="