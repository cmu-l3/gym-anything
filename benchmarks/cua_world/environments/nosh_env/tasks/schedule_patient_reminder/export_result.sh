#!/bin/bash
# Export script for schedule_patient_reminder
# verify the database state and export to JSON

echo "=== Exporting Task Result ==="

# 1. Capture Final Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Get Task Metadata
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TARGET_PID=3
TARGET_KEYWORD="Mammogram"
TARGET_DATE="2025-10-01"

# 3. Query Database for the Reminder
# We look for a reminder for PID 3, containing 'Mammogram', created AFTER task start
# Note: NOSH 'reminders' table usually has columns: reminder_id, pid, reminder, due_date, date_created
echo "Querying database..."

# Helper to escape for JSON
escape_json() {
    echo "$1" | sed 's/\\/\\\\/g' | sed 's/"/\\"/g' | sed 's/$//g' | sed ':a;N;$!ba;s/\n/ /g'
}

# Fetch the most recent relevant reminder
# We select records created recently or just order by ID descending
QUERY="SELECT reminder_id, reminder, due_date, date_created FROM reminders \
       WHERE pid=${TARGET_PID} \
       AND reminder LIKE '%${TARGET_KEYWORD}%' \
       ORDER BY reminder_id DESC LIMIT 1;"

DB_RESULT=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -e "$QUERY" 2>/dev/null)

FOUND="false"
REMINDER_ID=""
REMINDER_TEXT=""
DUE_DATE=""
DATE_CREATED=""

if [ -n "$DB_RESULT" ]; then
    FOUND="true"
    REMINDER_ID=$(echo "$DB_RESULT" | awk '{print $1}')
    # The remainder of the line is a bit tricky to parse with awk if text has spaces, 
    # but due_date/date_created are usually fixed format at the end.
    # Let's trust simpler parsing or just grab the whole line for verification logic.
    
    # Let's get fields individually to be safe
    REMINDER_TEXT=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -e "SELECT reminder FROM reminders WHERE reminder_id=$REMINDER_ID")
    DUE_DATE=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -e "SELECT due_date FROM reminders WHERE reminder_id=$REMINDER_ID")
    # NOSH often stores dates as YYYY-MM-DD or Unix timestamp. Assuming YYYY-MM-DD based on typical SQL
    
    # Get creation time (might be a timestamp column or date_created)
    # If date_created doesn't exist, we rely on the fact we deleted old ones in setup
    # But let's check current count vs 0
fi

# Sanitize
REMINDER_TEXT=$(escape_json "$REMINDER_TEXT")

# 4. Check if App is Running
APP_RUNNING="false"
if pgrep -f firefox >/dev/null; then
    APP_RUNNING="true"
fi

# 5. Create JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)

cat > "$TEMP_JSON" << EOF
{
    "found": $FOUND,
    "reminder_id": "${REMINDER_ID}",
    "reminder_text": "${REMINDER_TEXT}",
    "due_date": "${DUE_DATE}",
    "task_start_ts": ${TASK_START},
    "app_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# 6. Move to proper location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="