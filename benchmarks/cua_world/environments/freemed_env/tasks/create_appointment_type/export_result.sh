#!/bin/bash
# Export script for create_appointment_type task

echo "=== Exporting create_appointment_type result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end.png

# Schema-agnostic check: Dump the database to check for the newly created appointment type
echo "Querying final database state..."
mysqldump -u freemed -pfreemed freemed --skip-extended-insert > /tmp/final_dump.sql 2>/dev/null || true

# Check for our target string in the new dump
INITIAL_MATCH_COUNT=$(cat /tmp/initial_match_count 2>/dev/null || echo "0")
FINAL_MATCH_COUNT=$(grep -i "Telehealth Counseling" /tmp/final_dump.sql | wc -l || echo "0")
MATCHING_LINE=$(grep -i "Telehealth Counseling" /tmp/final_dump.sql | head -n 1)

DB_MATCH_FOUND="false"
DB_DURATION_MATCH="false"
CREATED_DURING_TASK="false"

echo "Initial match count: $INITIAL_MATCH_COUNT"
echo "Final match count: $FINAL_MATCH_COUNT"

# If count increased, the agent successfully added a record
if [ "$FINAL_MATCH_COUNT" -gt "$INITIAL_MATCH_COUNT" ]; then
    CREATED_DURING_TASK="true"
    DB_MATCH_FOUND="true"
    
    # Check if the exact row containing "Telehealth Counseling" also contains "45"
    if echo "$MATCHING_LINE" | grep -q "45"; then
        DB_DURATION_MATCH="true"
        echo "Found duration '45' in the created record."
    else
        echo "Duration '45' NOT found in the created record: $MATCHING_LINE"
    fi
fi

# Write results to a structured JSON using a temp file for safety
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "initial_match_count": $INITIAL_MATCH_COUNT,
    "final_match_count": $FINAL_MATCH_COUNT,
    "created_during_task": $CREATED_DURING_TASK,
    "db_match_found": $DB_MATCH_FOUND,
    "db_duration_match": $DB_DURATION_MATCH,
    "export_timestamp": "$(date -Iseconds)"
}
EOF

# Ensure safe overwrite and permissions
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Export completed successfully. Result JSON:"
cat /tmp/task_result.json
echo ""
echo "=== Export Complete ==="