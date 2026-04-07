#!/bin/bash
set -e
echo "=== Exporting task results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

MYSQL_CMD="mysql"
if ! mysql -u root -e "SELECT 1" &>/dev/null; then
    MYSQL_CMD="sudo mysql"
fi
DB_NAME="opensis"

# Get School Year used in setup
SYEAR=$(cat /tmp/syear.txt 2>/dev/null || echo "0")

# 1. Query Current State of the Course Section
# We find the course 'ENG101' and look up its section info
echo "Querying database..."
SECTION_DATA=$($MYSQL_CMD $DB_NAME -N -B -e "
    SELECT 
        cp.course_period_id,
        cp.room,
        cp.period_id,
        sp.title as period_title,
        sp.short_name as period_short
    FROM courses c
    JOIN course_periods cp ON c.course_id = cp.course_id
    JOIN school_periods sp ON cp.period_id = sp.period_id
    WHERE c.short_name = 'ENG101' 
    AND c.syear = $SYEAR
    AND cp.syear = $SYEAR
    LIMIT 1
" 2>/dev/null || echo "")

# Parse results
if [ -n "$SECTION_DATA" ]; then
    SECTION_FOUND="true"
    # Read tab separated values
    read -r CP_ID ROOM PERIOD_ID PERIOD_TITLE PERIOD_SHORT <<< "$SECTION_DATA"
else
    SECTION_FOUND="false"
    CP_ID=""
    ROOM=""
    PERIOD_ID=""
    PERIOD_TITLE=""
    PERIOD_SHORT=""
fi

# 2. Check Initial State (Anti-Gaming)
INITIAL_STATE=$(cat /tmp/initial_section_state.txt 2>/dev/null || echo "")
read -r INIT_PERIOD_ID INIT_ROOM <<< "$INITIAL_STATE"

# Check if changed
STATE_CHANGED="false"
if [ "$ROOM" != "$INIT_ROOM" ] || [ "$PERIOD_ID" != "$INIT_PERIOD_ID" ]; then
    STATE_CHANGED="true"
fi

# 3. Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 4. Create JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "section_found": $SECTION_FOUND,
    "current_room": "$ROOM",
    "current_period_id": "$PERIOD_ID",
    "current_period_title": "$PERIOD_TITLE",
    "current_period_short": "$PERIOD_SHORT",
    "initial_room": "$INIT_ROOM",
    "initial_period_id": "$INIT_PERIOD_ID",
    "state_changed": $STATE_CHANGED,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result exported:"
cat /tmp/task_result.json
echo "=== Export complete ==="