#!/bin/bash
# Export script for Add Employee task
# Saves all verification data to JSON file for verifier to read
# IMPORTANT: Only looks for the EXACT expected employee (Sarah Johnson)

echo "=== Exporting Add Employee Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# CRITICAL: Ensure Docker containers are running for verification
# This is the LAST chance to get containers running before verification
echo "Ensuring Docker containers are running (required for verification)..."
if ! ensure_docker_containers; then
    echo "WARNING: First attempt failed, trying aggressive recovery..."

    # Aggressive retry loop
    for attempt in {1..5}; do
        echo "Recovery attempt $attempt/5..."
        sleep 5
        if ensure_docker_containers; then
            echo "Recovery successful on attempt $attempt"
            break
        fi
    done
fi

# Final check - if containers still not running, create empty result to indicate failure
if ! docker exec timetrex-postgres pg_isready -U timetrex -d timetrex 2>/dev/null; then
    echo "FATAL: Database not accessible, creating failure result"
    cat > /tmp/add_employee_result.json << EOF
{
    "error": "Docker containers not running",
    "initial_employee_count": 0,
    "current_employee_count": 0,
    "employee_found": false,
    "employee": {},
    "export_timestamp": "$(date -Iseconds)"
}
EOF
    chmod 666 /tmp/add_employee_result.json 2>/dev/null || true
    exit 0
fi

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Get current employee count
CURRENT_COUNT=$(get_user_count)
INITIAL_COUNT=$(cat /tmp/initial_employee_count 2>/dev/null || echo "0")

echo "Employee count: initial=$INITIAL_COUNT, current=$CURRENT_COUNT"

# Debug: Show most recent employees to see what's actually in the database
echo ""
echo "=== DEBUG: Most recent users in database ==="
timetrex_query_full "SELECT id, first_name, last_name, employee_number, created_date FROM users ORDER BY created_date DESC LIMIT 5" 2>/dev/null
echo "=== END DEBUG ==="
echo ""

# Check if the EXACT target employee was added using CASE-INSENSITIVE matching
# STRICT: Only match Sarah Johnson - do NOT accept any other employee
echo "Checking for employee 'Sarah Johnson' (case-insensitive, strict match)..."
EMPLOYEE_ID=$(timetrex_query "SELECT id FROM users WHERE LOWER(TRIM(first_name))='sarah' AND LOWER(TRIM(last_name))='johnson' ORDER BY created_date DESC LIMIT 1" 2>/dev/null)

# Get employee details if found
EMPLOYEE_FOUND="false"
EMPLOYEE_FNAME=""
EMPLOYEE_LNAME=""
EMPLOYEE_NUMBER=""
EMPLOYEE_STATUS=""

if [ -n "$EMPLOYEE_ID" ] && [ "$EMPLOYEE_ID" != "" ]; then
    EMPLOYEE_FOUND="true"
    EMPLOYEE_FNAME=$(timetrex_query "SELECT first_name FROM users WHERE id='$EMPLOYEE_ID'" 2>/dev/null)
    EMPLOYEE_LNAME=$(timetrex_query "SELECT last_name FROM users WHERE id='$EMPLOYEE_ID'" 2>/dev/null)
    EMPLOYEE_NUMBER=$(timetrex_query "SELECT employee_number FROM users WHERE id='$EMPLOYEE_ID'" 2>/dev/null)
    EMPLOYEE_STATUS=$(timetrex_query "SELECT status_id FROM users WHERE id='$EMPLOYEE_ID'" 2>/dev/null)
    echo "Employee found: ID=$EMPLOYEE_ID, Name='$EMPLOYEE_FNAME $EMPLOYEE_LNAME', Number='$EMPLOYEE_NUMBER', Status=$EMPLOYEE_STATUS"
else
    echo "Employee 'Sarah Johnson' NOT found in database"
    # Report how many new employees were added (for debugging) but do NOT accept them
    if [ "$CURRENT_COUNT" -gt "$INITIAL_COUNT" ]; then
        NEW_COUNT=$((CURRENT_COUNT - INITIAL_COUNT))
        echo "Note: $NEW_COUNT new employee(s) added, but none named 'Sarah Johnson'"
    fi
fi

# Escape any special characters in employee data for JSON
EMPLOYEE_FNAME_ESCAPED=$(echo "$EMPLOYEE_FNAME" | sed 's/"/\\"/g')
EMPLOYEE_LNAME_ESCAPED=$(echo "$EMPLOYEE_LNAME" | sed 's/"/\\"/g')
EMPLOYEE_NUMBER_ESCAPED=$(echo "$EMPLOYEE_NUMBER" | sed 's/"/\\"/g')

# Create JSON in a temp file first, then move to avoid permission issues
TEMP_JSON=$(mktemp /tmp/add_employee_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "initial_employee_count": ${INITIAL_COUNT:-0},
    "current_employee_count": ${CURRENT_COUNT:-0},
    "employee_found": $EMPLOYEE_FOUND,
    "employee": {
        "id": "$EMPLOYEE_ID",
        "fname": "$EMPLOYEE_FNAME_ESCAPED",
        "lname": "$EMPLOYEE_LNAME_ESCAPED",
        "employee_number": "$EMPLOYEE_NUMBER_ESCAPED",
        "status_id": "$EMPLOYEE_STATUS"
    },
    "export_timestamp": "$(date -Iseconds)"
}
EOF

# Move temp file to final location (handles permission issues)
rm -f /tmp/add_employee_result.json 2>/dev/null || sudo rm -f /tmp/add_employee_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/add_employee_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/add_employee_result.json
chmod 666 /tmp/add_employee_result.json 2>/dev/null || sudo chmod 666 /tmp/add_employee_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Result JSON saved to /tmp/add_employee_result.json"
cat /tmp/add_employee_result.json

echo ""
echo "=== Export Complete ==="
