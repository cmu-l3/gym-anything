#!/bin/bash
# Export: create_user_account task
# Queries the database to verify the user was created correctly.

echo "=== Exporting create_user_account result ==="
source /workspace/scripts/task_utils.sh

# 1. Take final screenshot
take_screenshot /tmp/task_final_screenshot.png

# 2. Get Task Timestamps
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 3. Query Database for the specific user 'ariviera'
#    We join users -> person -> person_name and users -> user_role
#    Note: DB schema for OpenMRS:
#    - users: user_id, username, person_id, date_created
#    - person_name: person_id, given_name, family_name
#    - user_role: user_id, role

echo "Querying database for user 'ariviera'..."

# Helper to execute SQL and return JSON-like structure or specific fields
# We'll fetch raw fields and construct JSON in bash to avoid complex SQL-to-JSON logic inside MariaDB container

# Fetch User Basic Info
USER_INFO=$(omrs_db_query "
    SELECT u.user_id, u.username, u.date_created, pn.given_name, pn.family_name
    FROM users u
    JOIN person_name pn ON u.person_id = pn.person_id
    WHERE u.username = 'ariviera' AND u.retired = 0
    LIMIT 1;
" 2>/dev/null)

# Parse the tab-separated output
# Output format: user_id \t username \t date_created \t given_name \t family_name
USER_ID=$(echo "$USER_INFO" | awk '{print $1}')
USERNAME=$(echo "$USER_INFO" | awk '{print $2}')
DATE_CREATED_DB=$(echo "$USER_INFO" | awk '{print $3" "$4}') # Timestamp might have space
GIVEN_NAME=$(echo "$USER_INFO" | awk '{print $(NF-1)}')
FAMILY_NAME=$(echo "$USER_INFO" | awk '{print $NF}')

# Convert DB timestamp to epoch for comparison
if [ -n "$DATE_CREATED_DB" ]; then
    CREATED_EPOCH=$(date -d "$DATE_CREATED_DB" +%s 2>/dev/null || echo "0")
else
    CREATED_EPOCH="0"
fi

# Fetch Roles for this User
ROLES_LIST=""
if [ -n "$USER_ID" ]; then
    ROLES_LIST=$(omrs_db_query "SELECT role FROM user_role WHERE user_id = $USER_ID" 2>/dev/null | tr '\n' ',' | sed 's/,$//')
fi

# 4. Construct JSON Result
#    We use python to robustly create the JSON to handle potential empty vars/escaping
python3 -c "
import json
import sys

try:
    result = {
        'user_found': bool('$USER_ID'),
        'username': '$USERNAME',
        'given_name': '$GIVEN_NAME',
        'family_name': '$FAMILY_NAME',
        'roles': '$ROLES_LIST'.split(','),
        'created_epoch': int('$CREATED_EPOCH'),
        'task_start_epoch': int('$TASK_START'),
        'task_end_epoch': int('$TASK_END'),
        'is_newly_created': int('$CREATED_EPOCH') >= int('$TASK_START')
    }
except Exception as e:
    result = {'error': str(e)}

print(json.dumps(result, indent=2))
" > /tmp/task_result.json

# 5. Secure result file
chmod 666 /tmp/task_result.json

echo "Export complete. Result:"
cat /tmp/task_result.json