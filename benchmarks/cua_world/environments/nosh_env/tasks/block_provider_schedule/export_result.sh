#!/bin/bash
echo "=== Exporting Task Results ==="

# 1. Capture final screenshot
DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority scrot /tmp/task_final.png 2>/dev/null || true

# 2. Get Task Start Time
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 3. Query Database for Schedule Entries
#    We look for entries for provider 2 on today's date between 12:30 and 14:30 to catch the target event.
#    We select: id, provider_id, pid (patient id), start_time, end_time, reason, type
echo "Querying database for schedule entries..."

# Using docker exec to run SQL query and output as JSON-like CSV or raw text to be parsed
# Note: NOSH schedule table likely has 'start' and 'end' (or 'duration')
# Adjusting query based on typical NOSH schema: `schedule` table columns `provider_id`, `pid`, `start_time`, `end_time`, `reason`, `date`

DB_RESULT=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -e \
    "SELECT id, provider_id, pid, start_time, end_time, reason, date FROM schedule \
     WHERE provider_id=2 AND date=CURDATE() AND start_time >= '12:00:00' AND start_time <= '15:00:00';" 2>/dev/null)

echo "Raw DB Result: $DB_RESULT"

# 4. Construct JSON Result
#    We will parse the raw DB result in Python verifier, but here we just package it safely.
#    If multiple rows exist, we export them all.

# Create a temporary JSON file
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)

# Escape the DB result for JSON string inclusion
DB_RESULT_ESCAPED=$(echo "$DB_RESULT" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')

cat > "$TEMP_JSON" << EOF
{
    "task_start_timestamp": $TASK_START,
    "db_schedule_query_raw": $DB_RESULT_ESCAPED,
    "screenshot_path": "/tmp/task_final.png",
    "export_timestamp": "$(date +%s)"
}
EOF

# 5. Move to final location with permissive permissions
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Export complete. Result saved to /tmp/task_result.json"
cat /tmp/task_result.json