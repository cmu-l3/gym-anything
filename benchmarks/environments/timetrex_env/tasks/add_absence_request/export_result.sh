#!/bin/bash
# Export script for Add Absence Request task
# Saves all verification data to JSON file for verifier to read

echo "=== Exporting Absence Request Result ==="

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
    cat > /tmp/absence_request_result.json << EOF
{
    "error": "Docker containers not running",
    "initial_request_count": 0,
    "current_request_count": 0,
    "request_found": false,
    "request": {},
    "export_timestamp": "$(date -Iseconds)"
}
EOF
    chmod 666 /tmp/absence_request_result.json 2>/dev/null || true
    exit 0
fi

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Get current request count
CURRENT_COUNT=$(timetrex_query "SELECT COUNT(*) FROM request" 2>/dev/null || echo "0")
INITIAL_COUNT=$(cat /tmp/initial_request_count 2>/dev/null || echo "0")

echo "Request count: initial=$INITIAL_COUNT, current=$CURRENT_COUNT"

# Debug: Show most recent requests to see what's actually in the database
echo ""
echo "=== DEBUG: Most recent requests in database ==="
timetrex_query_full "SELECT r.id, r.user_id, u.first_name, u.last_name, u.employee_number, r.type_id, r.status_id, r.date_stamp FROM request r JOIN users u ON r.user_id = u.id ORDER BY r.created_date DESC LIMIT 5" 2>/dev/null
echo "=== END DEBUG ==="
echo ""

# Check for any new request records
REQUEST_FOUND="false"
REQUEST_ID=""
REQUEST_USER_ID=""
REQUEST_TYPE=""
REQUEST_STATUS=""
REQUEST_DATE=""
REQUEST_START_DATE=""
REQUEST_END_DATE=""
REQUEST_DURATION_DAYS="0"
EMPLOYEE_FNAME=""
EMPLOYEE_LNAME=""
EMPLOYEE_NUMBER=""
ABSENCE_TYPE_NAME=""

# Look for new requests
NEW_REQUEST=$(timetrex_query "SELECT id FROM request ORDER BY created_date DESC LIMIT 1" 2>/dev/null)

if [ -n "$NEW_REQUEST" ] && [ "$CURRENT_COUNT" -gt "$INITIAL_COUNT" ]; then
    REQUEST_FOUND="true"
    REQUEST_ID="$NEW_REQUEST"
    REQUEST_USER_ID=$(timetrex_query "SELECT user_id FROM request WHERE id='$REQUEST_ID'" 2>/dev/null)
    REQUEST_TYPE=$(timetrex_query "SELECT type_id FROM request WHERE id='$REQUEST_ID'" 2>/dev/null)
    REQUEST_STATUS=$(timetrex_query "SELECT status_id FROM request WHERE id='$REQUEST_ID'" 2>/dev/null)
    REQUEST_DATE=$(timetrex_query "SELECT date_stamp FROM request WHERE id='$REQUEST_ID'" 2>/dev/null)

    # Get start and end dates for duration validation
    # TimeTrex may store this in different ways depending on version
    REQUEST_START_DATE=$(timetrex_query "SELECT COALESCE(start_date, date_stamp)::date FROM request WHERE id='$REQUEST_ID'" 2>/dev/null)
    REQUEST_END_DATE=$(timetrex_query "SELECT COALESCE(end_date, date_stamp)::date FROM request WHERE id='$REQUEST_ID'" 2>/dev/null)

    # Calculate duration in days (end_date - start_date + 1)
    if [ -n "$REQUEST_START_DATE" ] && [ -n "$REQUEST_END_DATE" ]; then
        REQUEST_DURATION_DAYS=$(timetrex_query "SELECT (DATE '$REQUEST_END_DATE' - DATE '$REQUEST_START_DATE' + 1)" 2>/dev/null)
        if [ -z "$REQUEST_DURATION_DAYS" ]; then
            REQUEST_DURATION_DAYS="1"
        fi
    else
        REQUEST_DURATION_DAYS="1"
    fi

    # Get employee details
    EMPLOYEE_FNAME=$(timetrex_query "SELECT first_name FROM users WHERE id='$REQUEST_USER_ID'" 2>/dev/null)
    EMPLOYEE_LNAME=$(timetrex_query "SELECT last_name FROM users WHERE id='$REQUEST_USER_ID'" 2>/dev/null)
    EMPLOYEE_NUMBER=$(timetrex_query "SELECT employee_number FROM users WHERE id='$REQUEST_USER_ID'" 2>/dev/null)

    # Try to get the absence type name from absence_policy table
    ABSENCE_TYPE_NAME=$(timetrex_query "SELECT name FROM absence_policy WHERE id='$REQUEST_TYPE'" 2>/dev/null)
    # If not found, check if it's vacation based on type_id or other indicators
    if [ -z "$ABSENCE_TYPE_NAME" ]; then
        ABSENCE_TYPE_NAME="unknown"
    fi

    echo "New request found: ID=$REQUEST_ID, User=$REQUEST_USER_ID ($EMPLOYEE_FNAME $EMPLOYEE_LNAME #$EMPLOYEE_NUMBER)"
    echo "  Type=$REQUEST_TYPE ($ABSENCE_TYPE_NAME), Status=$REQUEST_STATUS"
    echo "  Date Range: $REQUEST_START_DATE to $REQUEST_END_DATE ($REQUEST_DURATION_DAYS days)"
else
    echo "No new requests found in database"
fi

# Escape any special characters for JSON
EMPLOYEE_FNAME_ESCAPED=$(echo "$EMPLOYEE_FNAME" | sed 's/"/\\"/g')
EMPLOYEE_LNAME_ESCAPED=$(echo "$EMPLOYEE_LNAME" | sed 's/"/\\"/g')
ABSENCE_TYPE_NAME_ESCAPED=$(echo "$ABSENCE_TYPE_NAME" | sed 's/"/\\"/g')

# Create JSON in a temp file first, then move to avoid permission issues
TEMP_JSON=$(mktemp /tmp/absence_request_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "initial_request_count": ${INITIAL_COUNT:-0},
    "current_request_count": ${CURRENT_COUNT:-0},
    "request_found": $REQUEST_FOUND,
    "request": {
        "id": "$REQUEST_ID",
        "user_id": "$REQUEST_USER_ID",
        "type_id": "$REQUEST_TYPE",
        "status_id": "$REQUEST_STATUS",
        "date_stamp": "$REQUEST_DATE",
        "start_date": "$REQUEST_START_DATE",
        "end_date": "$REQUEST_END_DATE",
        "duration_days": ${REQUEST_DURATION_DAYS:-1},
        "employee_fname": "$EMPLOYEE_FNAME_ESCAPED",
        "employee_lname": "$EMPLOYEE_LNAME_ESCAPED",
        "employee_number": "$EMPLOYEE_NUMBER",
        "absence_type_name": "$ABSENCE_TYPE_NAME_ESCAPED"
    },
    "export_timestamp": "$(date -Iseconds)"
}
EOF

# Move temp file to final location (handles permission issues)
rm -f /tmp/absence_request_result.json 2>/dev/null || sudo rm -f /tmp/absence_request_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/absence_request_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/absence_request_result.json
chmod 666 /tmp/absence_request_result.json 2>/dev/null || sudo chmod 666 /tmp/absence_request_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Result JSON saved to /tmp/absence_request_result.json"
cat /tmp/absence_request_result.json

echo ""
echo "=== Export Complete ==="
