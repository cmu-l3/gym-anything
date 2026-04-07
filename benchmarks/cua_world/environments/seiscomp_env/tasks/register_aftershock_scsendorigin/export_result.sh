#!/bin/bash
echo "=== Exporting task results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_COUNT=$(cat /tmp/initial_origin_count.txt 2>/dev/null || echo "0")
CURRENT_COUNT=$(seiscomp_db_query "SELECT COUNT(*) FROM Origin" 2>/dev/null || echo "0")

echo "Checking for new matching origin in database..."
# Allow slight float precision variance for lat/lon/depth
MATCHING_ORIGIN=$(seiscomp_db_query "
    SELECT po.publicID, o.latitude_value, o.longitude_value, o.depth_value, o.time_value
    FROM Origin o
    JOIN PublicObject po ON po._oid = o._oid
    WHERE o.latitude_value BETWEEN 37.24 AND 37.34
      AND o.longitude_value BETWEEN 136.73 AND 136.83
      AND o.depth_value BETWEEN 10.0 AND 14.0
      AND o.time_value BETWEEN '2024-01-01 16:18:42' AND '2024-01-01 16:18:52'
    ORDER BY o._oid DESC
    LIMIT 1
" 2>/dev/null || echo "")

ORIGIN_ID=""
DB_LAT="0"
DB_LON="0"
DB_DEPTH="0"
DB_TIME=""

if [ -n "$MATCHING_ORIGIN" ]; then
    ORIGIN_ID=$(echo "$MATCHING_ORIGIN" | awk '{print $1}')
    DB_LAT=$(echo "$MATCHING_ORIGIN" | awk '{print $2}')
    DB_LON=$(echo "$MATCHING_ORIGIN" | awk '{print $3}')
    DB_DEPTH=$(echo "$MATCHING_ORIGIN" | awk '{print $4}')
    DB_TIME=$(echo "$MATCHING_ORIGIN" | awk '{print $5" "$6}')
    echo "Found matching origin: ID=$ORIGIN_ID, Lat=$DB_LAT, Lon=$DB_LON, Depth=$DB_DEPTH, Time=$DB_TIME"
else
    echo "No matching origin found."
fi

# Check report file
REPORT_FILE="/home/ga/aftershock_report.txt"
REPORT_EXISTS="false"
REPORT_ID=""

if [ -f "$REPORT_FILE" ] && [ -s "$REPORT_FILE" ]; then
    REPORT_EXISTS="true"
    # Read the first line of the file (stripping any carriage returns)
    REPORT_ID=$(head -n 1 "$REPORT_FILE" | tr -d '\r\n ' | head -c 100)
    
    # Try fuzzy match if exact match isn't found
    ID_EXISTS=$(seiscomp_db_query "SELECT COUNT(*) FROM PublicObject WHERE publicID = '$REPORT_ID'" 2>/dev/null || echo "0")
    if [ "$ID_EXISTS" -eq "0" ]; then
        FUZZY_ID=$(grep -oP 'Origin/\S+' "$REPORT_FILE" | head -1 | tr -d '\r\n ')
        if [ -n "$FUZZY_ID" ]; then
            REPORT_ID="$FUZZY_ID"
        fi
    fi
    echo "Report file found. Parsed ID: $REPORT_ID"
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "initial_count": $INITIAL_COUNT,
    "current_count": $CURRENT_COUNT,
    "origin_found": $([ -n "$ORIGIN_ID" ] && echo "true" || echo "false"),
    "db_origin_id": "$ORIGIN_ID",
    "db_lat": "$DB_LAT",
    "db_lon": "$DB_LON",
    "db_depth": "$DB_DEPTH",
    "db_time": "$DB_TIME",
    "report_exists": $REPORT_EXISTS,
    "report_id": "$REPORT_ID"
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="