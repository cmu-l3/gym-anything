#!/bin/bash
echo "=== Exporting lock_marking_period results ==="

# Database Credentials
DB_USER="opensis_user"
DB_PASS="opensis_password_123"
DB_NAME="opensis"

# 1. Capture Final Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Extract Data from Database
# We need the status of Q1 and FY
echo "Querying database..."

# Helper to run query and return JSON string
# We select relevant fields for Q1 and FY
# school_id=1 is assumed from setup
DB_DATA=$(sudo mysql -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" -N -e "
SELECT 
    JSON_ARRAYAGG(
        JSON_OBJECT(
            'title', title,
            'short_name', short_name,
            'does_grades', does_grades,
            'does_comments', does_comments
        )
    )
FROM school_years 
WHERE school_id=1 AND (title='Quarter 1' OR short_name='FY');
" 2>/dev/null)

# If JSON_ARRAYAGG isn't available (older MariaDB), fall back to manual JSON construction using python
if [ -z "$DB_DATA" ] || [ "$DB_DATA" == "NULL" ]; then
    echo "Using python fallback for DB export..."
    RAW_DATA=$(sudo mysql -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" -N -B -e "SELECT title, short_name, does_grades, does_comments FROM school_years WHERE school_id=1 AND (title='Quarter 1' OR short_name='FY')")
    
    DB_DATA=$(python3 -c "
import sys, json
lines = sys.stdin.readlines()
data = []
for line in lines:
    parts = line.strip().split('\t')
    if len(parts) >= 4:
        data.append({
            'title': parts[0],
            'short_name': parts[1],
            'does_grades': parts[2],
            'does_comments': parts[3]
        })
print(json.dumps(data))
" <<< "$RAW_DATA")
fi

# 3. Create Result JSON
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Check if browser is still running
APP_RUNNING="false"
if pgrep -f "chrome\|chromium" > /dev/null; then
    APP_RUNNING="true"
fi

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_running": $APP_RUNNING,
    "marking_periods": $DB_DATA,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location
sudo mv "$TEMP_JSON" /tmp/task_result.json
sudo chmod 666 /tmp/task_result.json

echo "Export complete. Result:"
cat /tmp/task_result.json