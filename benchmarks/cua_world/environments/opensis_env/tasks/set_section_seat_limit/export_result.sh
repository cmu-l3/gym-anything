#!/bin/bash
echo "=== Exporting set_section_seat_limit results ==="

# 1. Capture Final Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Database Credentials
DB_USER="opensis_user"
DB_PASS="opensis_password_123"
DB_NAME="opensis"
MYSQL_CMD="mysql -u $DB_USER -p$DB_PASS $DB_NAME -N -B"

# 3. Query Target Course (ART-205) Seats
echo "Querying target course..."
TARGET_QUERY="SELECT cp.total_seats FROM course_periods cp JOIN courses c ON cp.course_id = c.course_id WHERE c.course_code = 'ART-205' AND cp.short_name = '01' LIMIT 1"
TARGET_SEATS=$($MYSQL_CMD -e "$TARGET_QUERY" 2>/dev/null || echo "-1")

# 4. Query Control Course (ART-101) Seats
echo "Querying control course..."
CONTROL_QUERY="SELECT cp.total_seats FROM course_periods cp JOIN courses c ON cp.course_id = c.course_id WHERE c.course_code = 'ART-101' AND cp.short_name = '01' LIMIT 1"
CONTROL_SEATS=$($MYSQL_CMD -e "$CONTROL_QUERY" 2>/dev/null || echo "-1")

# 5. Check System Status
APP_RUNNING=$(pgrep -f "chrome\|chromium" > /dev/null && echo "true" || echo "false")

# 6. Create JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "target_seats": "$TARGET_SEATS",
    "control_seats": "$CONTROL_SEATS",
    "app_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png",
    "timestamp": $(date +%s)
}
EOF

# 7. Secure Move
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="