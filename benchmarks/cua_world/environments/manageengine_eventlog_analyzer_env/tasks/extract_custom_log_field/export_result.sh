#!/bin/bash
# Export results for extract_custom_log_field task

echo "=== Exporting Task Results ==="

source /workspace/scripts/task_utils.sh

# 1. Capture Final Screenshot
take_screenshot /tmp/task_final.png

# 2. Check File System Configuration
# ManageEngine often stores extraction patterns in XML/Conf files under /opt/ManageEngine/EventLog/conf
# We look for the field name and the regex pattern.
ELA_HOME="/opt/ManageEngine/EventLog"
CONF_DIR="$ELA_HOME/conf"

# Search for the field name in config files
FIELD_FOUND_IN_CONF=$(grep -r "FinTransactionID" "$CONF_DIR" 2>/dev/null | head -n 1)
REGEX_FOUND_IN_CONF=$(grep -r "TXN" "$CONF_DIR" 2>/dev/null | grep -v "log" | head -n 1)

# Check timestamp of the found file to ensure it was modified during task
FILE_MODIFIED_DURING_TASK="false"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

if [ -n "$FIELD_FOUND_IN_CONF" ]; then
    # Extract filename from grep output (file:match)
    MATCH_FILE=$(echo "$FIELD_FOUND_IN_CONF" | cut -d: -f1)
    if [ -f "$MATCH_FILE" ]; then
        FILE_MTIME=$(stat -c %Y "$MATCH_FILE" 2>/dev/null || echo "0")
        if [ "$FILE_MTIME" -ge "$TASK_START" ]; then
            FILE_MODIFIED_DURING_TASK="true"
        fi
    fi
fi

# 3. Database Check (Fallback/Confirmation)
# We query the internal DB for the field name. 
# Table names might vary by version, so we try a few likely candidates for patterns/fields.
# We just dump a broad search query to text.

DB_SEARCH_RESULT=""
# Try searching the 'pattern' or 'field' related tables
DB_SEARCH_RESULT=$(ela_db_query "SELECT * FROM pattern WHERE pattern_name LIKE '%FinTransactionID%' OR regex LIKE '%TXN-%'" 2>/dev/null)
if [ -z "$DB_SEARCH_RESULT" ]; then
    # Try searching specific field definitions if table exists
    DB_SEARCH_RESULT=$(ela_db_query "SELECT * FROM ulpattern WHERE pattern_name LIKE '%FinTransactionID%'" 2>/dev/null)
fi

# 4. Construct Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $TASK_START,
    "conf_match": "$(echo "$FIELD_FOUND_IN_CONF" | sed 's/"/\\"/g')",
    "regex_match": "$(echo "$REGEX_FOUND_IN_CONF" | sed 's/"/\\"/g')",
    "file_modified_during_task": $FILE_MODIFIED_DURING_TASK,
    "db_record_found": "$(if [ -n "$DB_SEARCH_RESULT" ]; then echo "true"; else echo "false"; fi)",
    "db_data": "$(echo "$DB_SEARCH_RESULT" | sed 's/"/\\"/g' | head -c 200)"
}
EOF

# Move result to standard location
rm -f /tmp/task_result.json 2>/dev/null
mv "$TEMP_JSON" /tmp/task_result.json
chmod 644 /tmp/task_result.json

echo "Export complete."
cat /tmp/task_result.json