#!/bin/bash
set -euo pipefail

echo "=== Setting up edit_user_account_settings task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt
echo "Task start time: $(cat /tmp/task_start_time.txt)"

# Ensure SEB Server is accessible
wait_for_seb_server 120

echo "=== Preparing target user data ==="
# Define fallback if seb_db_query is not available
if ! type seb_db_query >/dev/null 2>&1; then
    seb_db_query() {
        docker exec seb-server-mariadb mysql -u root -psebserver123 SEBServer -N -e "$1" 2>/dev/null
    }
fi

# Check if emily.chen already exists
EXISTING_ID=$(seb_db_query "SELECT id FROM user WHERE username='emily.chen';" | tr -d '[:space:]')

if [ -n "$EXISTING_ID" ]; then
    echo "User emily.chen exists, resetting fields to initial state..."
    seb_db_query "UPDATE user SET timezone='UTC', email='emily.chen@westlake-university.edu', name='Emily', surname='Chen' WHERE id=${EXISTING_ID};"
else
    echo "User emily.chen not found, creating..."
    # Get a valid password hash from super-admin
    ADMIN_HASH=$(seb_db_query "SELECT password FROM user WHERE username='super-admin' LIMIT 1;" | tr -d '[:space:]')
    if [ -z "$ADMIN_HASH" ]; then
        ADMIN_HASH='$2a$08$YTmE6wQMib07kKOodkN3Ye6Nkr8fRcWYJH8Mqf0dUL8zMmvCQjhxG'
    fi
    
    # Insert new user into database
    seb_db_query "INSERT INTO user (institution_id, uuid, creation_date, name, surname, username, password, email, language, timezone, active) VALUES (1, UUID(), NOW(), 'Emily', 'Chen', 'emily.chen', '${ADMIN_HASH}', 'emily.chen@westlake-university.edu', 'en', 'UTC', 1);"
    
    # Assign EXAM_SUPPORTER role
    NEW_ID=$(seb_db_query "SELECT id FROM user WHERE username='emily.chen';" | tr -d '[:space:]')
    if [ -n "$NEW_ID" ]; then
        seb_db_query "INSERT INTO user_role (user_id, role_name) VALUES (${NEW_ID}, 'EXAM_SUPPORTER');"
    fi
fi

# Record initial state
INITIAL_TZ=$(seb_db_query "SELECT timezone FROM user WHERE username='emily.chen';" | tr -d '[:space:]')
INITIAL_EMAIL=$(seb_db_query "SELECT email FROM user WHERE username='emily.chen';" | tr -d '[:space:]')
echo "$INITIAL_TZ" > /tmp/initial_timezone.txt
echo "$INITIAL_EMAIL" > /tmp/initial_email.txt

echo "Verified initial state: Timezone=$INITIAL_TZ, Email=$INITIAL_EMAIL"

# Launch Firefox and navigate to SEB Server Login page
launch_firefox "http://localhost:8080"
sleep 5

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="