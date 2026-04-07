#!/bin/bash
echo "=== Exporting refine_magnitude_outliers_scolv result ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Check if scolv is running
APP_RUNNING=$(pgrep -f "scolv" > /dev/null && echo "true" || echo "false")

# Extract the latest Event's publicID
EVENT_ID=$(seiscomp_db_query "SELECT publicID FROM Event ORDER BY _oid DESC LIMIT 1" 2>/dev/null || echo "")

XML_DUMP_EXISTS="false"
if [ -n "$EVENT_ID" ]; then
    echo "Dumping Event XML for event: $EVENT_ID"
    # Dump the event, its origins, magnitudes, and station contributions to XML
    su - ga -c "SEISCOMP_ROOT=$SEISCOMP_ROOT PATH=$SEISCOMP_ROOT/bin:\$PATH \
        LD_LIBRARY_PATH=$SEISCOMP_ROOT/lib:\$LD_LIBRARY_PATH \
        seiscomp exec scxmldump -E '$EVENT_ID' -P -M -f > /tmp/event_dump.xml" 2>/dev/null
    
    if [ -s "/tmp/event_dump.xml" ]; then
        XML_DUMP_EXISTS="true"
        echo "Event XML successfully dumped to /tmp/event_dump.xml"
    else
        echo "WARNING: scxmldump produced an empty file or failed."
    fi
else
    echo "WARNING: Could not find any Event in the database."
fi

# Read initial magnitude ID
INITIAL_MAG_ID=$(cat /tmp/initial_mag_id.txt 2>/dev/null || echo "NONE")

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_was_running": $APP_RUNNING,
    "event_id": "$EVENT_ID",
    "initial_mag_id": "$INITIAL_MAG_ID",
    "xml_dump_exists": $XML_DUMP_EXISTS,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

if [ "$XML_DUMP_EXISTS" = "true" ]; then
    chmod 666 /tmp/event_dump.xml 2>/dev/null || sudo chmod 666 /tmp/event_dump.xml 2>/dev/null || true
fi

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="