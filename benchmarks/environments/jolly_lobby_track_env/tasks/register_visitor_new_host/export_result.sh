#!/bin/bash
echo "=== Exporting register_visitor_new_host result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. Take final screenshot for VLM verification
take_screenshot /tmp/task_final.png

# 2. Identify the database file to check for persistence
# Lobby Track usually stores data in an Access .mdb or SQL Compact .sdf file in ProgramData or Common AppData
DB_FILE=$(find /home/ga/.wine -type f \( -iname "*.mdb" -o -iname "*.sdf" \) -print0 | xargs -0 ls -t | head -n 1)

DB_MODIFIED="false"
HOST_FOUND_IN_DB="false"
VISITOR_FOUND_IN_DB="false"
DB_PATH=""

if [ -n "$DB_FILE" ] && [ -f "$DB_FILE" ]; then
    DB_PATH="$DB_FILE"
    echo "Checking database file: $DB_FILE"
    
    # Check modification time
    TASK_START=$(cat /tmp/register_visitor_new_host_start_time 2>/dev/null || echo "0")
    DB_MTIME=$(stat -c %Y "$DB_FILE" 2>/dev/null || echo "0")
    
    if [ "$DB_MTIME" -gt "$TASK_START" ]; then
        DB_MODIFIED="true"
    fi
    
    # Grep for strings in the binary DB file (common way to check data entry without proprietary tools)
    # Using -a to treat binary as text
    if grep -a "Amanda" "$DB_FILE" >/dev/null && grep -a "Sterling" "$DB_FILE" >/dev/null; then
        HOST_FOUND_IN_DB="true"
    fi
    
    if grep -a "Jordan" "$DB_FILE" >/dev/null && grep -a "Lee" "$DB_FILE" >/dev/null; then
        VISITOR_FOUND_IN_DB="true"
    fi
else
    echo "WARNING: No database file found to verify."
fi

# 3. Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "db_file_found": $( [ -n "$DB_PATH" ] && echo "true" || echo "false" ),
    "db_modified_during_task": $DB_MODIFIED,
    "host_string_in_db": $HOST_FOUND_IN_DB,
    "visitor_string_in_db": $VISITOR_FOUND_IN_DB,
    "final_screenshot_path": "/tmp/task_final.png",
    "timestamp": "$(date -Iseconds)"
}
EOF

# Save result with permissions
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="