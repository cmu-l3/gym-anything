#!/bin/bash
# Export script for Clock In Employee task
# Saves all verification data to JSON file for verifier to read

echo "=== Exporting Clock In Result ==="

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
    cat > /tmp/clock_in_result.json << EOF
{
    "error": "Docker containers not running",
    "initial_punch_count": 0,
    "current_punch_count": 0,
    "punch_found": false,
    "punch": {},
    "export_timestamp": "$(date -Iseconds)"
}
EOF
    chmod 666 /tmp/clock_in_result.json 2>/dev/null || true
    exit 0
fi

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Get current punch count
CURRENT_COUNT=$(get_punch_count)
INITIAL_COUNT=$(cat /tmp/initial_punch_count 2>/dev/null || echo "0")
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

echo "Punch count: initial=$INITIAL_COUNT, current=$CURRENT_COUNT"

# Debug: Show most recent punches to see what's actually in the database
echo ""
echo "=== DEBUG: Most recent punches in database ==="
timetrex_query_full "SELECT p.id, p.user_id, u.first_name, u.last_name, u.employee_number, p.status_id, p.type_id, p.time_stamp FROM punch p JOIN users u ON p.user_id = u.id ORDER BY p.time_stamp DESC LIMIT 5" 2>/dev/null
echo "=== END DEBUG ==="
echo ""

# Check for any new punch records added during this task
PUNCH_FOUND="false"
PUNCH_ID=""
PUNCH_USER_ID=""
PUNCH_STATUS=""
PUNCH_TYPE=""
PUNCH_TIMESTAMP=""
EMPLOYEE_FNAME=""
EMPLOYEE_LNAME=""
EMPLOYEE_NUMBER=""

# Look for new punches (those with timestamp after task start)
NEW_PUNCH=$(timetrex_query "SELECT id FROM punch ORDER BY time_stamp DESC LIMIT 1" 2>/dev/null)

if [ -n "$NEW_PUNCH" ] && [ "$CURRENT_COUNT" -gt "$INITIAL_COUNT" ]; then
    PUNCH_FOUND="true"
    PUNCH_ID="$NEW_PUNCH"
    PUNCH_USER_ID=$(timetrex_query "SELECT user_id FROM punch WHERE id='$PUNCH_ID'" 2>/dev/null)
    PUNCH_STATUS=$(timetrex_query "SELECT status_id FROM punch WHERE id='$PUNCH_ID'" 2>/dev/null)
    PUNCH_TYPE=$(timetrex_query "SELECT type_id FROM punch WHERE id='$PUNCH_ID'" 2>/dev/null)
    PUNCH_TIMESTAMP=$(timetrex_query "SELECT time_stamp FROM punch WHERE id='$PUNCH_ID'" 2>/dev/null)

    # Get employee details for the punched user
    EMPLOYEE_FNAME=$(timetrex_query "SELECT first_name FROM users WHERE id='$PUNCH_USER_ID'" 2>/dev/null)
    EMPLOYEE_LNAME=$(timetrex_query "SELECT last_name FROM users WHERE id='$PUNCH_USER_ID'" 2>/dev/null)
    EMPLOYEE_NUMBER=$(timetrex_query "SELECT employee_number FROM users WHERE id='$PUNCH_USER_ID'" 2>/dev/null)

    echo "New punch found: ID=$PUNCH_ID, User=$PUNCH_USER_ID ($EMPLOYEE_FNAME $EMPLOYEE_LNAME #$EMPLOYEE_NUMBER), Status=$PUNCH_STATUS, Type=$PUNCH_TYPE, Timestamp=$PUNCH_TIMESTAMP"
else
    echo "No new punches found in database"
fi

# Escape any special characters for JSON
EMPLOYEE_FNAME_ESCAPED=$(echo "$EMPLOYEE_FNAME" | sed 's/"/\\"/g')
EMPLOYEE_LNAME_ESCAPED=$(echo "$EMPLOYEE_LNAME" | sed 's/"/\\"/g')

# Create JSON in a temp file first, then move to avoid permission issues
TEMP_JSON=$(mktemp /tmp/clock_in_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "initial_punch_count": ${INITIAL_COUNT:-0},
    "current_punch_count": ${CURRENT_COUNT:-0},
    "punch_found": $PUNCH_FOUND,
    "punch": {
        "id": "$PUNCH_ID",
        "user_id": "$PUNCH_USER_ID",
        "status_id": "$PUNCH_STATUS",
        "type_id": "$PUNCH_TYPE",
        "timestamp": "$PUNCH_TIMESTAMP",
        "employee_fname": "$EMPLOYEE_FNAME_ESCAPED",
        "employee_lname": "$EMPLOYEE_LNAME_ESCAPED",
        "employee_number": "$EMPLOYEE_NUMBER"
    },
    "task_start_timestamp": "$TASK_START",
    "export_timestamp": "$(date -Iseconds)"
}
EOF

# Move temp file to final location (handles permission issues)
rm -f /tmp/clock_in_result.json 2>/dev/null || sudo rm -f /tmp/clock_in_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/clock_in_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/clock_in_result.json
chmod 666 /tmp/clock_in_result.json 2>/dev/null || sudo chmod 666 /tmp/clock_in_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Result JSON saved to /tmp/clock_in_result.json"
cat /tmp/clock_in_result.json

echo ""
echo "=== Export Complete ==="
