#!/bin/bash
echo "=== Exporting Proximity Network results ==="

# Ensure safe PATH
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64
export PATH=$PATH:$JAVA_HOME/bin

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot
take_screenshot /tmp/task_final.png

# 1. Export Schema Information (Class definition)
echo "Exporting schema..."
SCHEMA_JSON=$(curl -s -u "${ORIENTDB_AUTH}" "${ORIENTDB_URL}/database/demodb")

# 2. Export Created Edges with connected vertex details
# We fetch: Edge properties, Out vertex (Hotel) lat/lon/city, In vertex (Restaurant) lat/lon/city
echo "Exporting edge data..."
EDGES_QUERY="SELECT Distance, City, out.Name as HotelName, out.City as HotelCity, out.Latitude as HotelLat, out.Longitude as HotelLon, in.Name as RestName, in.City as RestCity, in.Latitude as RestLat, in.Longitude as RestLon FROM NearBy"

EDGES_JSON=$(orientdb_sql "demodb" "$EDGES_QUERY")

# 3. Check Report File
REPORT_PATH="/home/ga/proximity_report.txt"
REPORT_EXISTS="false"
REPORT_CONTENT=""
REPORT_CREATED_DURING_TASK="false"

if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_MTIME=$(stat -c %Y "$REPORT_PATH" 2>/dev/null || echo "0")
    if [ "$REPORT_MTIME" -gt "$TASK_START" ]; then
        REPORT_CREATED_DURING_TASK="true"
    fi
    # Read first 50 lines of report to avoid huge JSON if they dump garbage
    REPORT_CONTENT=$(head -n 50 "$REPORT_PATH" | base64 -w 0)
fi

# 4. Check if Firefox is running
APP_RUNNING=$(pgrep -f "firefox" > /dev/null && echo "true" || echo "false")

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_was_running": $APP_RUNNING,
    "schema": $SCHEMA_JSON,
    "edges_data": $EDGES_JSON,
    "report": {
        "exists": $REPORT_EXISTS,
        "created_during_task": $REPORT_CREATED_DURING_TASK,
        "content_base64": "$REPORT_CONTENT"
    },
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
echo "=== Export complete ==="