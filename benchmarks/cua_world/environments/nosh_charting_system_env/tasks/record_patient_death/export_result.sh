#!/bin/bash
echo "=== Exporting Record Patient Death Result ==="

# 1. Get Task Information
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
PID=$(cat /tmp/target_pid.txt 2>/dev/null || echo "")

if [ -z "$PID" ]; then
    # Fallback lookup if PID file missing
    PID=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -e \
        "SELECT pid FROM demographics WHERE firstname='Albert' AND lastname='Zweig' LIMIT 1;")
fi

echo "Checking database for PID: $PID"

# 2. Query Database for Patient Record
# We dump the specific row to JSON-compatible format or just raw text to be parsed by python
# We select key columns likely to hold the death info
DB_RECORD=""
if [ -n "$PID" ]; then
    # Fetch relevant columns. Note: Column names for death date might vary (date_deceased, deceased_date, etc.)
    # We'll fetch the whole row to be safe and let Python parser find the date
    DB_RECORD=$(docker exec nosh-db mysql -uroot -prootpassword nosh -B -e \
        "SELECT * FROM demographics WHERE pid=$PID \G")
fi

# 3. Capture Evidence
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 4. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)

# Safe string encoding for the DB record
ENCODED_RECORD=$(echo "$DB_RECORD" | jq -R -s '.')

cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "target_pid": "$PID",
    "db_record_dump": $ENCODED_RECORD,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
echo "=== Export Complete ==="