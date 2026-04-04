#!/bin/bash
echo "=== Exporting Temporal Travel Anomaly Result ==="

source /workspace/scripts/task_utils.sh

# Record timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot
take_screenshot /tmp/task_final.png ga
SCREENSHOT_EXISTS="false"
[ -f /tmp/task_final.png ] && SCREENSHOT_EXISTS="true"

# Check Output File
OUTPUT_PATH="/home/ga/suspicious_travelers.json"
OUTPUT_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
OUTPUT_SIZE="0"

if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$OUTPUT_PATH" 2>/dev/null || echo "0")
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# Query Database State (Did agent mark profiles as Suspicious?)
echo "Querying database for flagged profiles..."
DB_FLAGGED_PROFILES=$(curl -s -X POST \
    -u "root:GymAnything123!" \
    -H "Content-Type: application/json" \
    -d '{"command":"SELECT Email FROM Profiles WHERE Suspicious = true"}' \
    "http://localhost:2480/command/demodb/sql" 2>/dev/null | \
    python3 -c "import sys,json; print(json.dumps([r.get('Email') for r in json.load(sys.stdin).get('result', [])]))" 2>/dev/null || echo "[]")

# Query Database State (Check schema for Suspicious property)
DB_SCHEMA_PROP_EXISTS=$(curl -s -X POST \
    -u "root:GymAnything123!" \
    -H "Content-Type: application/json" \
    -d '{"command":"SELECT FROM (SELECT expand(properties) FROM (SELECT from schema:Profiles)) WHERE name = '\''Suspicious'\''"}' \
    "http://localhost:2480/command/demodb/sql" 2>/dev/null | \
    python3 -c "import sys,json; res=json.load(sys.stdin).get('result',[]); print('true' if res else 'false')" 2>/dev/null || echo "false")

# Retrieve Ground Truth (hidden)
GROUND_TRUTH_PATH="/var/lib/orientdb/ground_truth_anomalies.json"
GROUND_TRUTH="[]"
if [ -f "$GROUND_TRUTH_PATH" ]; then
    GROUND_TRUTH=$(cat "$GROUND_TRUTH_PATH")
fi

# Construct Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_file_exists": $OUTPUT_EXISTS,
    "output_file_created_during_task": $FILE_CREATED_DURING_TASK,
    "output_file_path": "$OUTPUT_PATH",
    "db_flagged_emails": $DB_FLAGGED_PROFILES,
    "db_property_exists": $DB_SCHEMA_PROP_EXISTS,
    "ground_truth_emails": $GROUND_TRUTH,
    "screenshot_path": "/tmp/task_final.png",
    "screenshot_exists": $SCREENSHOT_EXISTS
}
EOF

# Move to standard location
rm -f /tmp/task_result.json 2>/dev/null || true
mv "$TEMP_JSON" /tmp/task_result.json
chmod 644 /tmp/task_result.json

echo "Export complete. Result saved to /tmp/task_result.json"