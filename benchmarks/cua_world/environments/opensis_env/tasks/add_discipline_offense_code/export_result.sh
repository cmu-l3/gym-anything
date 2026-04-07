#!/bin/bash
echo "=== Exporting task results ==="

# 1. Capture Final Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Get Task Metadata
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_MAX_ID=$(cat /tmp/initial_max_id.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 3. Query Database for Results
# We look for the record and also check its ID against the initial max ID
echo "Querying database..."

# Query to find the specific record
# Note: Using -N (skip headers) and -B (batch/tab-separated) for clean parsing
DB_RESULT=$(mysql -u opensis_user -p'opensis_password_123' opensis -N -B -e \
    "SELECT id, title, sort_order FROM discipline_field_usage WHERE title LIKE '%Cyberbullying%' LIMIT 1;" 2>/dev/null)

RECORD_FOUND="false"
RECORD_ID="0"
RECORD_TITLE=""
RECORD_SORT=""

if [ -n "$DB_RESULT" ]; then
    RECORD_FOUND="true"
    RECORD_ID=$(echo "$DB_RESULT" | cut -f1)
    RECORD_TITLE=$(echo "$DB_RESULT" | cut -f2)
    RECORD_SORT=$(echo "$DB_RESULT" | cut -f3)
fi

# Check if it was created during this session (ID > Initial Max ID)
# This prevents pre-existing data gaming if cleanup failed, or just confirms it's new.
IS_NEW_RECORD="false"
if [ "$RECORD_FOUND" = "true" ] && [ "$RECORD_ID" -gt "$INITIAL_MAX_ID" ]; then
    IS_NEW_RECORD="true"
fi

# 4. Check if Browser is Still Running (Availability Check)
APP_RUNNING="false"
if pgrep -f "chrome\|chromium" > /dev/null; then
    APP_RUNNING="true"
fi

# 5. Create JSON Result
# Using a temp file to avoid permission issues before copying
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "record_found": $RECORD_FOUND,
    "record_details": {
        "id": $RECORD_ID,
        "title": "$RECORD_TITLE",
        "sort_order": "$RECORD_SORT"
    },
    "is_new_record": $IS_NEW_RECORD,
    "initial_max_id": $INITIAL_MAX_ID,
    "app_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location with permissive permissions
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="