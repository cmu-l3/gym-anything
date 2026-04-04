#!/bin/bash
echo "=== Exporting Create User Account Results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# 1. Query OpenMRS API for the created user
TARGET_USERNAME="anita.sharma"
echo "Querying API for user: $TARGET_USERNAME"

# Helper to execute python for JSON parsing
parse_json() {
    python3 -c "import sys, json; print(json.load(sys.stdin)$1)" 2>/dev/null || echo ""
}

# Fetch user details
# We use curl with -k for self-signed certs
USER_JSON=$(curl -sk -u "${BAHMNI_ADMIN_USERNAME}:${BAHMNI_ADMIN_PASSWORD}" \
    "${OPENMRS_API_URL}/user?q=${TARGET_USERNAME}&v=full")

# Check if results exist
USER_FOUND="false"
RESULTS_COUNT=$(echo "$USER_JSON" | parse_json ".get('results', []) | length")

if [ "$RESULTS_COUNT" -gt "0" ]; then
    USER_FOUND="true"
    # Get the first result (should be the user)
    USER_DATA=$(echo "$USER_JSON" | parse_json ".get('results', [])[0]")
    
    # Extract verification details
    ACTUAL_USERNAME=$(echo "$USER_DATA" | python3 -c "import sys, json; print(json.load(sys.stdin).get('username', ''))")
    
    # Person details
    PERSON_DATA=$(echo "$USER_DATA" | python3 -c "import sys, json; print(json.dumps(json.load(sys.stdin).get('person', {})))")
    GIVEN_NAME=$(echo "$PERSON_DATA" | python3 -c "import sys, json; print(json.load(sys.stdin).get('preferredName', {}).get('givenName', ''))")
    FAMILY_NAME=$(echo "$PERSON_DATA" | python3 -c "import sys, json; print(json.load(sys.stdin).get('preferredName', {}).get('familyName', ''))")
    GENDER=$(echo "$PERSON_DATA" | python3 -c "import sys, json; print(json.load(sys.stdin).get('gender', ''))")
    
    # Role details
    ROLES_LIST=$(echo "$USER_DATA" | python3 -c "import sys, json; roles=json.load(sys.stdin).get('roles', []); print(json.dumps([r.get('display') for r in roles]))")
    
    echo "User Found: $ACTUAL_USERNAME"
    echo "Name: $GIVEN_NAME $FAMILY_NAME"
    echo "Gender: $GENDER"
    echo "Roles: $ROLES_LIST"
else
    echo "User not found in API results"
    ACTUAL_USERNAME=""
    GIVEN_NAME=""
    FAMILY_NAME=""
    GENDER=""
    ROLES_LIST="[]"
fi

# 2. Get User Count Change
INITIAL_COUNT=$(cat /tmp/initial_user_count.txt 2>/dev/null || echo "0")
FINAL_COUNT=$(docker exec bahmni-openmrsdb mysql -u openmrs-user -ppassword openmrs -N -e "SELECT COUNT(*) FROM users WHERE retired = 0;" 2>/dev/null || echo "0")
echo "User count: $INITIAL_COUNT -> $FINAL_COUNT"

# 3. Check Browser State (to verify they are in Admin area)
# We check the window title from the final screenshot moment or current state
WINDOW_TITLE=$(DISPLAY=:1 XAUTHORITY="${XAUTHORITY_PATH}" wmctrl -l | grep -i "Epiphany" | tail -1 || echo "Unknown")

# 4. Construct Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "user_found": $USER_FOUND,
    "actual_username": "$ACTUAL_USERNAME",
    "actual_given_name": "$GIVEN_NAME",
    "actual_family_name": "$FAMILY_NAME",
    "actual_gender": "$GENDER",
    "actual_roles": $ROLES_LIST,
    "initial_user_count": $INITIAL_COUNT,
    "final_user_count": $FINAL_COUNT,
    "window_title": "$WINDOW_TITLE",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Save to public location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result JSON saved:"
cat /tmp/task_result.json
echo "=== Export Complete ==="