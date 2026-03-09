#!/bin/bash
set -e
echo "=== Exporting task result: Create Provider Account ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Capture final screenshot
take_screenshot /tmp/task_final.png

# --- Database Verification ---

TARGET_USER="schen"

# Helper function to safely get a single value from DB
get_user_field() {
    local field="$1"
    # Use librehealth_query but trim whitespace
    val=$(librehealth_query "SELECT $field FROM users WHERE username='$TARGET_USER' LIMIT 1" 2>/dev/null || echo "")
    echo "$val" | xargs
}

# Check if user exists
USER_EXISTS="false"
COUNT_CHECK=$(librehealth_query "SELECT COUNT(*) FROM users WHERE username='$TARGET_USER'" 2>/dev/null || echo "0")
if [ "$COUNT_CHECK" -gt 0 ]; then
    USER_EXISTS="true"
fi

# Extract fields
FNAME=$(get_user_field "fname")
LNAME=$(get_user_field "lname")
MNAME=$(get_user_field "mname")
NPI=$(get_user_field "npi")
TAXID=$(get_user_field "federaltaxid")
AUTHORIZED=$(get_user_field "authorized")
SPECIALTY=$(get_user_field "specialty")
FACILITY_ID=$(get_user_field "facility_id")

# Check security table (password existence)
SECURE_EXISTS="false"
SECURE_COUNT=$(librehealth_query "SELECT COUNT(*) FROM users_secure WHERE username='$TARGET_USER'" 2>/dev/null || echo "0")
if [ "$SECURE_COUNT" -gt 0 ]; then
    SECURE_EXISTS="true"
fi

# Anti-gaming: Check total user counts
INITIAL_COUNT=$(cat /tmp/initial_user_count.txt 2>/dev/null || echo "0")
FINAL_COUNT=$(librehealth_query "SELECT COUNT(*) FROM users" 2>/dev/null || echo "0")
COUNT_INCREASED="false"
if [ "$FINAL_COUNT" -gt "$INITIAL_COUNT" ]; then
    COUNT_INCREASED="true"
fi

# Create JSON Result
# Using python to safely dump JSON handles special characters/escaping better than bash string concat
python3 -c "
import json
import sys

result = {
    'user_exists': $USER_EXISTS,
    'secure_entry_exists': $SECURE_EXISTS,
    'fields': {
        'fname': '''$FNAME''',
        'lname': '''$LNAME''',
        'mname': '''$MNAME''',
        'npi': '''$NPI''',
        'federaltaxid': '''$TAXID''',
        'authorized': '''$AUTHORIZED''',
        'specialty': '''$SPECIALTY''',
        'facility_id': '''$FACILITY_ID'''
    },
    'counts': {
        'initial': $INITIAL_COUNT,
        'final': $FINAL_COUNT,
        'increased': $COUNT_INCREASED
    },
    'screenshot_path': '/tmp/task_final.png'
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=4)
"

# Set permissions so the host can copy it
chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="