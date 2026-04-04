#!/bin/bash
echo "=== Exporting schema_constraints result ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Check if OrientDB is running
ORIENTDB_RUNNING="false"
if pgrep -f "orientdb" > /dev/null; then
    ORIENTDB_RUNNING="true"
fi

# Export the final schema state
# We dump the entire database configuration which includes schema, classes, and properties
echo "Exporting final schema..."
SCHEMA_EXPORT_PATH="/tmp/final_schema.json"

# Use curl to get the database info
HTTP_CODE=$(curl -s -w "%{http_code}" -o "$SCHEMA_EXPORT_PATH" \
    -u "${ORIENTDB_AUTH}" \
    "${ORIENTDB_URL}/database/demodb")

SCHEMA_RETRIEVED="false"
if [ "$HTTP_CODE" = "200" ] && [ -s "$SCHEMA_EXPORT_PATH" ]; then
    SCHEMA_RETRIEVED="true"
else
    echo "ERROR: Failed to retrieve schema (HTTP $HTTP_CODE)"
    echo "{}" > "$SCHEMA_EXPORT_PATH"
fi

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "orientdb_running": $ORIENTDB_RUNNING,
    "schema_retrieved": $SCHEMA_RETRIEVED,
    "schema_snapshot": $(cat "$SCHEMA_EXPORT_PATH"),
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location with permission handling
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"
rm -f "$SCHEMA_EXPORT_PATH"

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="