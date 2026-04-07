#!/bin/bash
echo "=== Exporting add_medication_dictionary_entry result ==="

source /workspace/scripts/task_utils.sh

# Record end time
date +%s > /tmp/task_end_time.txt

# Take final screenshot
take_screenshot /tmp/task_final_screenshot.png

# Retrieve data state
MED_TABLE=$(cat /tmp/med_table_name.txt 2>/dev/null || echo "medication")
INITIAL_COUNT=$(cat /tmp/initial_med_count.txt 2>/dev/null || echo "0")
CURRENT_COUNT=$(freemed_query "SELECT COUNT(*) FROM $MED_TABLE" 2>/dev/null || echo "0")

# Dump the 5 most recently added rows to catch the new medication
# We replace tabs with spaces and escape quotes for safe JSON injection
RECENT_ROWS=$(freemed_query "SELECT * FROM $MED_TABLE ORDER BY id DESC LIMIT 5" 2>/dev/null | tr '\t' ' ' | sed 's/"/\\"/g' | sed ':a;N;$!ba;s/\n/\\n/g')

# Search specifically for Wegovy or semaglutide to provide a direct match signal
TARGET_MATCH=$(freemed_query "SELECT * FROM $MED_TABLE WHERE medname LIKE '%Wegovy%' OR medgeneric LIKE '%semaglutide%' LIMIT 1" 2>/dev/null | tr '\t' ' ' | sed 's/"/\\"/g' | sed ':a;N;$!ba;s/\n/\\n/g')

# Package into JSON
TEMP_JSON=$(mktemp /tmp/med_export.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "med_table": "$MED_TABLE",
    "initial_count": ${INITIAL_COUNT:-0},
    "current_count": ${CURRENT_COUNT:-0},
    "recent_rows": "$RECENT_ROWS",
    "target_match": "$TARGET_MATCH",
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to standard location securely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result JSON saved to /tmp/task_result.json"
cat /tmp/task_result.json

echo "=== Export Complete ==="