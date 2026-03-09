#!/bin/bash
echo "=== Exporting Identify Local Leaders Result ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Check if output file exists
OUTPUT_FILE="/home/ga/local_leaders.json"
OUTPUT_EXISTS="false"
FILE_CREATED_DURING_TASK="false"

if [ -f "$OUTPUT_FILE" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_FILE" 2>/dev/null || echo "0")
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# 2. Extract Database State for Verification
# We query the database to get the actual values the agent calculated.
# We fetch Email, FriendCount, and IsLocalLeader for all profiles involved in our topology.
echo "Querying database state..."

DB_STATE_JSON=$(orientdb_sql "demodb" "SELECT Email, FriendCount, IsLocalLeader FROM Profiles WHERE Email IN ['john.smith@example.com', 'maria.garcia@example.com', 'luca.rossi@example.com', 'anna.mueller@example.com', 'james.brown@example.com', 'emma.white@example.com', 'yuki.tanaka@example.com']")

# 3. Check Schema
# We verify if properties exist
SCHEMA_JSON=$(curl -s -u "${ORIENTDB_AUTH}" "${ORIENTDB_URL}/database/demodb")

# 4. Take final screenshot
take_screenshot /tmp/task_final.png

# 5. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_exists": $OUTPUT_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "output_file_path": "$OUTPUT_FILE",
    "db_state": $DB_STATE_JSON,
    "schema_snapshot": $SCHEMA_JSON,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="