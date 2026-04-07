#!/bin/bash
# Export script for update_operating_hours task
# Queries the NOSH database for schedule changes and exports to JSON

echo "=== Exporting task results ==="

# 1. Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Get Task Timing
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 3. Query Database for Current Schedule State
# We need Friday Close, Monday Close (control), and Friday Open (control)
# practice_id=1 is the default practice created in setup
echo "Querying database..."
DB_RESULT=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -e \
    "SELECT fri_c, mon_c, fri_o FROM practiceinfo WHERE practice_id=1;" 2>/dev/null)

# Parse the tab-separated result
# Default to empty if query fails
FRI_CLOSE=$(echo "$DB_RESULT" | awk '{print $1}')
MON_CLOSE=$(echo "$DB_RESULT" | awk '{print $2}')
FRI_OPEN=$(echo "$DB_RESULT" | awk '{print $3}')

echo "Current DB State -> Fri Close: $FRI_CLOSE, Mon Close: $MON_CLOSE, Fri Open: $FRI_OPEN"

# 4. Check if app is running (Firefox)
APP_RUNNING="false"
if pgrep -f firefox > /dev/null; then
    APP_RUNNING="true"
fi

# 5. Construct JSON Result
# Using a temp file to avoid permission issues
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)

cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_was_running": $APP_RUNNING,
    "schedule_data": {
        "fri_close": "$FRI_CLOSE",
        "mon_close": "$MON_CLOSE",
        "fri_open": "$FRI_OPEN"
    },
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# 6. Move to final location (accessible by verifier)
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="