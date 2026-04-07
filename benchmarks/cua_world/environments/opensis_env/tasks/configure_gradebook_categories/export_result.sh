#!/bin/bash
echo "=== Exporting Task Results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Database credentials
DB_USER="opensis_user"
DB_PASS="opensis_password_123"
DB_NAME="opensis"
MYSQL_CMD="mysql -u $DB_USER -p$DB_PASS $DB_NAME"

# 1. Identify the Course Period ID
# We need to find the ID for Mathematics 101, Period 1
echo "Resolving Course Period ID..."
CP_ID=$($MYSQL_CMD -N -e "
    SELECT cp.course_period_id 
    FROM course_periods cp
    JOIN courses c ON cp.course_id = c.course_id
    WHERE c.course_title = 'Mathematics 101' AND cp.title = 'Period 1'
    LIMIT 1;
")

if [ -z "$CP_ID" ]; then
    echo "ERROR: Course Period not found!"
    CP_ID="0"
fi
echo "Found Course Period ID: $CP_ID"

# 2. Extract Categories for this Course Period
# We output as JSON array of objects
echo "Extracting categories..."
# Note: Schema for categories typically 'gradebook_assignment_types' with columns 'title', 'weight'/'final_grade_percent'
CATEGORIES_JSON=$($MYSQL_CMD -N -e "
    SELECT JSON_ARRAYAGG(
        JSON_OBJECT(
            'title', title,
            'weight', final_grade_percent,
            'id', assignment_type_id
        )
    )
    FROM gradebook_assignment_types
    WHERE course_period_id = $CP_ID;
")

# Handle empty result (mysql returns NULL for empty aggregation sometimes)
if [ "$CATEGORIES_JSON" == "NULL" ] || [ -z "$CATEGORIES_JSON" ]; then
    CATEGORIES_JSON="[]"
fi

# 3. Check App State (is Chrome running?)
APP_RUNNING=$(pgrep -f "chrome\|chromium" > /dev/null && echo "true" || echo "false")

# 4. Take Final Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 5. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "course_period_id": $CP_ID,
    "categories": $CATEGORIES_JSON,
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location (handle permissions)
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="