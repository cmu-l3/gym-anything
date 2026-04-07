#!/bin/bash
set -e
echo "=== Exporting relocate_class_section results ==="

# 1. Capture Final Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Database Credentials
DB_USER="opensis_user"
DB_PASS="opensis_password_123"
DB_NAME="opensis"
MYSQL_CMD="mysql -u $DB_USER -p$DB_PASS $DB_NAME -N -B -e"

# 3. Read Initial IDs
if [ ! -f /tmp/initial_ids.json ]; then
    echo "ERROR: Initial IDs file not found!"
    # Create dummy file to fail gracefully
    echo "{}" > /tmp/task_result.json
    exit 0
fi

# Use python to parse JSON in bash (robust way)
parse_json() {
    python3 -c "import json, sys; print(json.load(sys.stdin)['$1'])" < /tmp/initial_ids.json
}

TARGET_SECTION_ID=$(parse_json "target_section_id")
DISTRACTOR_SECTION_ID=$(parse_json "distractor_section_id")
SCIENCE_LAB_ID=$(parse_json "science_lab_id")
ROOM_304_ID=$(parse_json "room_304_id")
COURSE_ID=$(parse_json "course_id")

# 4. Query Current State
echo "Querying database state..."

# Get current room ID for the target section (Period 2)
CURRENT_TARGET_ROOM=$($MYSQL_CMD "SELECT room_id FROM course_periods WHERE course_period_id=$TARGET_SECTION_ID LIMIT 1" 2>/dev/null || echo "NULL")

# Get current room ID for the distractor section (Period 3)
CURRENT_DISTRACTOR_ROOM=$($MYSQL_CMD "SELECT room_id FROM course_periods WHERE course_period_id=$DISTRACTOR_SECTION_ID LIMIT 1" 2>/dev/null || echo "NULL")

# Get last updated timestamp for the target section
# OpenSIS usually has updated_at or similar, but course_periods might not. 
# We'll rely on value comparison primarily.

# 5. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "initial_ids": $(cat /tmp/initial_ids.json),
    "current_state": {
        "target_section_room_id": "$CURRENT_TARGET_ROOM",
        "distractor_section_room_id": "$CURRENT_DISTRACTOR_ROOM"
    },
    "task_start_time": $(cat /tmp/task_start_time.txt 2>/dev/null || echo 0),
    "task_end_time": $(date +%s),
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# 6. Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="