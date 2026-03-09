#!/bin/bash
# Export script for Create Schedule task
# Saves all verification data to JSON file for verifier to read

echo "=== Exporting Create Schedule Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# CRITICAL: Ensure Docker containers are running for verification
echo "Ensuring Docker containers are running (required for verification)..."
if ! ensure_docker_containers; then
    echo "WARNING: First attempt failed, trying aggressive recovery..."
    for attempt in {1..5}; do
        echo "Recovery attempt $attempt/5..."
        sleep 5
        if ensure_docker_containers; then
            echo "Recovery successful on attempt $attempt"
            break
        fi
    done
fi

# Final check
if ! docker exec timetrex-postgres pg_isready -U timetrex -d timetrex 2>/dev/null; then
    echo "FATAL: Database not accessible, creating failure result"
    cat > /tmp/create_schedule_result.json << EOF
{
    "error": "Docker containers not running",
    "initial_schedule_count": 0,
    "current_schedule_count": 0,
    "schedule_found": false,
    "schedule": {},
    "export_timestamp": "$(date -Iseconds)"
}
EOF
    chmod 666 /tmp/create_schedule_result.json 2>/dev/null || true
    exit 0
fi

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Get current schedule count
CURRENT_COUNT=$(get_schedule_count)
INITIAL_COUNT=$(cat /tmp/initial_schedule_count 2>/dev/null || echo "0")

echo "Schedule count: initial=$INITIAL_COUNT, current=$CURRENT_COUNT"

# Debug: Show most recent schedules to see what's actually in the database
echo ""
echo "=== DEBUG: Most recent schedules in database ==="
timetrex_query_full "SELECT s.id, s.user_id, u.first_name, u.last_name, u.employee_number, s.start_time, s.end_time, s.date_stamp FROM schedule s JOIN users u ON s.user_id = u.id ORDER BY s.created_date DESC LIMIT 5" 2>/dev/null
echo "=== END DEBUG ==="
echo ""

# Check for any new schedule records
SCHEDULE_FOUND="false"
SCHEDULE_ID=""
SCHEDULE_USER_ID=""
SCHEDULE_START=""
SCHEDULE_END=""
SCHEDULE_DATE=""
EMPLOYEE_FNAME=""
EMPLOYEE_LNAME=""
EMPLOYEE_NUMBER=""

# Look for new schedules
NEW_SCHEDULE=$(timetrex_query "SELECT id FROM schedule ORDER BY created_date DESC LIMIT 1" 2>/dev/null)

if [ -n "$NEW_SCHEDULE" ] && [ "$CURRENT_COUNT" -gt "$INITIAL_COUNT" ]; then
    SCHEDULE_FOUND="true"
    SCHEDULE_ID="$NEW_SCHEDULE"
    SCHEDULE_USER_ID=$(timetrex_query "SELECT user_id FROM schedule WHERE id='$SCHEDULE_ID'" 2>/dev/null)
    SCHEDULE_START=$(timetrex_query "SELECT start_time FROM schedule WHERE id='$SCHEDULE_ID'" 2>/dev/null)
    SCHEDULE_END=$(timetrex_query "SELECT end_time FROM schedule WHERE id='$SCHEDULE_ID'" 2>/dev/null)
    SCHEDULE_DATE=$(timetrex_query "SELECT date_stamp FROM schedule WHERE id='$SCHEDULE_ID'" 2>/dev/null)

    # Get employee details
    EMPLOYEE_FNAME=$(timetrex_query "SELECT first_name FROM users WHERE id='$SCHEDULE_USER_ID'" 2>/dev/null)
    EMPLOYEE_LNAME=$(timetrex_query "SELECT last_name FROM users WHERE id='$SCHEDULE_USER_ID'" 2>/dev/null)
    EMPLOYEE_NUMBER=$(timetrex_query "SELECT employee_number FROM users WHERE id='$SCHEDULE_USER_ID'" 2>/dev/null)

    echo "New schedule found: ID=$SCHEDULE_ID, User=$SCHEDULE_USER_ID ($EMPLOYEE_FNAME $EMPLOYEE_LNAME #$EMPLOYEE_NUMBER), Start=$SCHEDULE_START, End=$SCHEDULE_END, Date=$SCHEDULE_DATE"
else
    echo "No new schedules found in database"
fi

# Escape any special characters for JSON
EMPLOYEE_FNAME_ESCAPED=$(echo "$EMPLOYEE_FNAME" | sed 's/"/\\"/g')
EMPLOYEE_LNAME_ESCAPED=$(echo "$EMPLOYEE_LNAME" | sed 's/"/\\"/g')

# Create JSON in a temp file first, then move to avoid permission issues
TEMP_JSON=$(mktemp /tmp/create_schedule_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "initial_schedule_count": ${INITIAL_COUNT:-0},
    "current_schedule_count": ${CURRENT_COUNT:-0},
    "schedule_found": $SCHEDULE_FOUND,
    "schedule": {
        "id": "$SCHEDULE_ID",
        "user_id": "$SCHEDULE_USER_ID",
        "start_time": "$SCHEDULE_START",
        "end_time": "$SCHEDULE_END",
        "date_stamp": "$SCHEDULE_DATE",
        "employee_fname": "$EMPLOYEE_FNAME_ESCAPED",
        "employee_lname": "$EMPLOYEE_LNAME_ESCAPED",
        "employee_number": "$EMPLOYEE_NUMBER"
    },
    "export_timestamp": "$(date -Iseconds)"
}
EOF

# Move temp file to final location (handles permission issues)
rm -f /tmp/create_schedule_result.json 2>/dev/null || sudo rm -f /tmp/create_schedule_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/create_schedule_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/create_schedule_result.json
chmod 666 /tmp/create_schedule_result.json 2>/dev/null || sudo chmod 666 /tmp/create_schedule_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Result JSON saved to /tmp/create_schedule_result.json"
cat /tmp/create_schedule_result.json

echo ""
echo "=== Export Complete ==="
