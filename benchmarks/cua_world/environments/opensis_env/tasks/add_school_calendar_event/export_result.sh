#!/bin/bash
echo "=== Exporting task results ==="

# Record task end info
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Take final screenshot
echo "Capturing final screenshot..."
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Query Database for the Event
DB_USER="opensis_user"
DB_PASS="opensis_password_123"
DB_NAME="opensis"

echo "Querying database for calendar event..."

# Query to find the event based on title or date
# OpenSIS usually uses 'calendar_events' with columns: id, school_date, title, description, school_id
# Note: Column names might vary slightly by version, checking common ones
QUERY="SELECT title, school_date, description FROM calendar_events WHERE title LIKE '%Science Fair%' OR school_date = '2026-05-20' ORDER BY id DESC LIMIT 1"

# Execute query and format as JSON-like structure (tab separated)
RESULT=$(mysql -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" -N -B -e "$QUERY" 2>/dev/null || echo "")

EVENT_FOUND="false"
TITLE=""
DATE=""
DESC=""
IS_HOLIDAY="false" # Default to false unless we find specific evidence

if [ -n "$RESULT" ]; then
    EVENT_FOUND="true"
    # Parse tab separated result
    TITLE=$(echo "$RESULT" | cut -f1)
    DATE=$(echo "$RESULT" | cut -f2)
    DESC=$(echo "$RESULT" | cut -f3)
    
    # Check if it was marked as a holiday (often a separate flag or type)
    # We'll check the 'school_years' or 'calendar_events' table for holiday flag if it exists
    HOLIDAY_CHECK=$(mysql -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" -N -B -e "SELECT 1 FROM calendar_events WHERE (title LIKE '%Science Fair%' OR school_date = '2026-05-20') AND (type='Holiday' OR title LIKE '%Holiday%')" 2>/dev/null || echo "0")
    if [ "$HOLIDAY_CHECK" == "1" ]; then
        IS_HOLIDAY="true"
    fi
fi

# 3. Create JSON Result
# Use a temp file to avoid permission issues
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)

# Escape strings for JSON
TITLE_ESC=$(echo "$TITLE" | sed 's/"/\\"/g')
DESC_ESC=$(echo "$DESC" | sed 's/"/\\"/g')

cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "event_found": $EVENT_FOUND,
    "event_data": {
        "title": "$TITLE_ESC",
        "date": "$DATE",
        "description": "$DESC_ESC",
        "is_holiday": $IS_HOLIDAY
    },
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="