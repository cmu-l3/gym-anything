#!/bin/bash
echo "=== Exporting generate_demand_routes result ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot
take_screenshot /tmp/task_final.png

TRIPS_FILE="/home/ga/SUMO_Output/random_trips.trips.xml"
ROUTES_FILE="/home/ga/SUMO_Output/random_trips.rou.xml"

TRIPS_EXISTS="false"
TRIPS_SIZE="0"
TRIPS_MTIME="0"
if [ -f "$TRIPS_FILE" ]; then
    TRIPS_EXISTS="true"
    TRIPS_SIZE=$(stat -c %s "$TRIPS_FILE" 2>/dev/null || echo "0")
    TRIPS_MTIME=$(stat -c %Y "$TRIPS_FILE" 2>/dev/null || echo "0")
fi

ROUTES_EXISTS="false"
ROUTES_SIZE="0"
ROUTES_MTIME="0"
if [ -f "$ROUTES_FILE" ]; then
    ROUTES_EXISTS="true"
    ROUTES_SIZE=$(stat -c %s "$ROUTES_FILE" 2>/dev/null || echo "0")
    ROUTES_MTIME=$(stat -c %Y "$ROUTES_FILE" 2>/dev/null || echo "0")
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "trips_exists": $TRIPS_EXISTS,
    "trips_size": $TRIPS_SIZE,
    "trips_mtime": $TRIPS_MTIME,
    "routes_exists": $ROUTES_EXISTS,
    "routes_size": $ROUTES_SIZE,
    "routes_mtime": $ROUTES_MTIME,
    "screenshot_path": "/tmp/task_final.png",
    "timestamp": "$(date -Iseconds)"
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