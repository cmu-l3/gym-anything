#!/bin/bash
# Export script for Create Provider User task
# Queries database and saves verification data to JSON

echo "=== Exporting Create Provider User Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
echo "Capturing final screenshot..."
take_screenshot /tmp/task_final_screenshot.png
if [ -f /tmp/task_final_screenshot.png ]; then
    SCREENSHOT_SIZE=$(stat -c %s /tmp/task_final_screenshot.png 2>/dev/null || echo "0")
    echo "Final screenshot captured: ${SCREENSHOT_SIZE} bytes"
fi

# Expected values
TARGET_USERNAME="jsmith_np"
EXPECTED_FNAME="Jennifer"
EXPECTED_LNAME="Smith"

# Get initial state values
INITIAL_MAX_ID=$(cat /tmp/initial_max_user_id 2>/dev/null || echo "0")
INITIAL_USER_COUNT=$(cat /tmp/initial_user_count 2>/dev/null || echo "0")
INITIAL_AUTH_COUNT=$(cat /tmp/initial_auth_user_count 2>/dev/null || echo "0")
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
TASK_END=$(date +%s)

echo "Initial state: max_id=$INITIAL_MAX_ID, user_count=$INITIAL_USER_COUNT, auth_count=$INITIAL_AUTH_COUNT"
echo "Task duration: $TASK_START to $TASK_END"

# Get current counts
CURRENT_USER_COUNT=$(docker exec openemr-mysql mysql -u openemr -popenemr openemr -N -e "SELECT COUNT(*) FROM users" 2>/dev/null || echo "0")
CURRENT_AUTH_COUNT=$(docker exec openemr-mysql mysql -u openemr -popenemr openemr -N -e "SELECT COUNT(*) FROM users WHERE authorized=1" 2>/dev/null || echo "0")
CURRENT_MAX_ID=$(docker exec openemr-mysql mysql -u openemr -popenemr openemr -N -e "SELECT COALESCE(MAX(id), 0) FROM users" 2>/dev/null || echo "0")

echo "Current state: max_id=$CURRENT_MAX_ID, user_count=$CURRENT_USER_COUNT, auth_count=$CURRENT_AUTH_COUNT"

# Debug: Show recent users
echo ""
echo "=== DEBUG: Most recent users in database ==="
docker exec openemr-mysql mysql -u openemr -popenemr openemr -e "SELECT id, username, fname, lname, authorized, active, npi FROM users ORDER BY id DESC LIMIT 5" 2>/dev/null
echo "=== END DEBUG ==="
echo ""

# Query for the target user by username
echo "Checking for user '$TARGET_USERNAME'..."
USER_DATA=$(docker exec openemr-mysql mysql -u openemr -popenemr openemr -N -e "SELECT id, username, fname, lname, mname, authorized, active, npi, federaltaxid, suffix, calendar, facility_id FROM users WHERE username='$TARGET_USERNAME' LIMIT 1" 2>/dev/null)

# Parse user data
USER_FOUND="false"
USER_ID=""
USER_USERNAME=""
USER_FNAME=""
USER_LNAME=""
USER_MNAME=""
USER_AUTHORIZED=""
USER_ACTIVE=""
USER_NPI=""
USER_TAXID=""
USER_SUFFIX=""
USER_CALENDAR=""
USER_FACILITY=""

if [ -n "$USER_DATA" ]; then
    USER_FOUND="true"
    USER_ID=$(echo "$USER_DATA" | cut -f1)
    USER_USERNAME=$(echo "$USER_DATA" | cut -f2)
    USER_FNAME=$(echo "$USER_DATA" | cut -f3)
    USER_LNAME=$(echo "$USER_DATA" | cut -f4)
    USER_MNAME=$(echo "$USER_DATA" | cut -f5)
    USER_AUTHORIZED=$(echo "$USER_DATA" | cut -f6)
    USER_ACTIVE=$(echo "$USER_DATA" | cut -f7)
    USER_NPI=$(echo "$USER_DATA" | cut -f8)
    USER_TAXID=$(echo "$USER_DATA" | cut -f9)
    USER_SUFFIX=$(echo "$USER_DATA" | cut -f10)
    USER_CALENDAR=$(echo "$USER_DATA" | cut -f11)
    USER_FACILITY=$(echo "$USER_DATA" | cut -f12)

    echo ""
    echo "User found:"
    echo "  ID: $USER_ID"
    echo "  Username: $USER_USERNAME"
    echo "  Name: $USER_FNAME $USER_MNAME $USER_LNAME"
    echo "  Suffix: $USER_SUFFIX"
    echo "  Authorized: $USER_AUTHORIZED"
    echo "  Active: $USER_ACTIVE"
    echo "  NPI: $USER_NPI"
    echo "  Tax ID: $USER_TAXID"
    echo "  Calendar: $USER_CALENDAR"
    echo "  Facility: $USER_FACILITY"
else
    echo "User '$TARGET_USERNAME' NOT found in database"
    
    # Check if any new users were created
    if [ "$CURRENT_USER_COUNT" -gt "$INITIAL_USER_COUNT" ]; then
        NEW_USERS=$((CURRENT_USER_COUNT - INITIAL_USER_COUNT))
        echo "Note: $NEW_USERS new user(s) were created, but not with expected username"
        echo "Newest user:"
        docker exec openemr-mysql mysql -u openemr -popenemr openemr -e "SELECT id, username, fname, lname, authorized FROM users ORDER BY id DESC LIMIT 1" 2>/dev/null
    fi
fi

# Determine if user was created during task (ID > initial max)
CREATED_DURING_TASK="false"
if [ -n "$USER_ID" ] && [ "$USER_ID" -gt "$INITIAL_MAX_ID" ]; then
    CREATED_DURING_TASK="true"
    echo "User was created during task (id=$USER_ID > initial_max=$INITIAL_MAX_ID)"
else
    echo "User was NOT created during task (may have pre-existed)"
fi

# Validate specific fields
NAME_CORRECT="false"
if [ "$(echo "$USER_FNAME" | tr '[:upper:]' '[:lower:]')" = "$(echo "$EXPECTED_FNAME" | tr '[:upper:]' '[:lower:]')" ] && \
   [ "$(echo "$USER_LNAME" | tr '[:upper:]' '[:lower:]')" = "$(echo "$EXPECTED_LNAME" | tr '[:upper:]' '[:lower:]')" ]; then
    NAME_CORRECT="true"
fi

AUTHORIZED_SET="false"
if [ "$USER_AUTHORIZED" = "1" ]; then
    AUTHORIZED_SET="true"
fi

ACTIVE_SET="false"
if [ "$USER_ACTIVE" = "1" ]; then
    ACTIVE_SET="true"
fi

NPI_RECORDED="false"
if [ -n "$USER_NPI" ] && [ "$USER_NPI" != "NULL" ] && [ "$USER_NPI" != "" ]; then
    NPI_RECORDED="true"
fi

# Escape special characters for JSON
USER_FNAME_ESC=$(echo "$USER_FNAME" | sed 's/"/\\"/g')
USER_LNAME_ESC=$(echo "$USER_LNAME" | sed 's/"/\\"/g')
USER_MNAME_ESC=$(echo "$USER_MNAME" | sed 's/"/\\"/g')
USER_SUFFIX_ESC=$(echo "$USER_SUFFIX" | sed 's/"/\\"/g')
USER_NPI_ESC=$(echo "$USER_NPI" | sed 's/"/\\"/g')
USER_TAXID_ESC=$(echo "$USER_TAXID" | sed 's/"/\\"/g')

# Create result JSON
TEMP_JSON=$(mktemp /tmp/provider_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_timestamp": $TASK_START,
    "task_end_timestamp": $TASK_END,
    "initial_state": {
        "max_user_id": $INITIAL_MAX_ID,
        "user_count": $INITIAL_USER_COUNT,
        "authorized_user_count": $INITIAL_AUTH_COUNT
    },
    "current_state": {
        "max_user_id": $CURRENT_MAX_ID,
        "user_count": $CURRENT_USER_COUNT,
        "authorized_user_count": $CURRENT_AUTH_COUNT
    },
    "target_username": "$TARGET_USERNAME",
    "user_found": $USER_FOUND,
    "user": {
        "id": "${USER_ID:-0}",
        "username": "$USER_USERNAME",
        "fname": "$USER_FNAME_ESC",
        "lname": "$USER_LNAME_ESC",
        "mname": "$USER_MNAME_ESC",
        "suffix": "$USER_SUFFIX_ESC",
        "authorized": "${USER_AUTHORIZED:-0}",
        "active": "${USER_ACTIVE:-0}",
        "npi": "$USER_NPI_ESC",
        "federaltaxid": "$USER_TAXID_ESC",
        "calendar": "${USER_CALENDAR:-0}",
        "facility_id": "${USER_FACILITY:-0}"
    },
    "validation": {
        "created_during_task": $CREATED_DURING_TASK,
        "name_correct": $NAME_CORRECT,
        "authorized_set": $AUTHORIZED_SET,
        "active_set": $ACTIVE_SET,
        "npi_recorded": $NPI_RECORDED
    },
    "screenshot_path": "/tmp/task_final_screenshot.png",
    "export_timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location with permission handling
rm -f /tmp/create_provider_result.json 2>/dev/null || sudo rm -f /tmp/create_provider_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/create_provider_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/create_provider_result.json
chmod 666 /tmp/create_provider_result.json 2>/dev/null || sudo chmod 666 /tmp/create_provider_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Result JSON saved to /tmp/create_provider_result.json"
cat /tmp/create_provider_result.json
echo ""
echo "=== Export Complete ==="