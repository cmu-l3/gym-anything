#!/bin/bash
echo "=== Exporting edit_dive_site_gps result ==="

export DISPLAY="${DISPLAY:-:1}"

# Collect task metadata for verifier
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_MTIME=$(cat /tmp/ssrf_initial_mtime.txt 2>/dev/null || echo "0")
INITIAL_GPS_COUNT=$(cat /tmp/initial_gps_count.txt 2>/dev/null || echo "0")

OUTPUT_PATH="/home/ga/Documents/dives.ssrf"
if [ -f "$OUTPUT_PATH" ]; then
    CURRENT_MTIME=$(stat -c%Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    OUTPUT_SIZE=$(stat -c%s "$OUTPUT_PATH" 2>/dev/null || echo "0")
    OUTPUT_EXISTS="true"
else
    CURRENT_MTIME="0"
    OUTPUT_SIZE="0"
    OUTPUT_EXISTS="false"
fi

APP_RUNNING=$(pgrep -f "subsurface" > /dev/null && echo "true" || echo "false")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# Format JSON result output
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "initial_mtime": $INITIAL_MTIME,
    "current_mtime": $CURRENT_MTIME,
    "initial_gps_count": $INITIAL_GPS_COUNT,
    "output_exists": $OUTPUT_EXISTS,
    "output_size_bytes": $OUTPUT_SIZE,
    "app_was_running": $APP_RUNNING
}
EOF

# Move to final location with permission handling
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="