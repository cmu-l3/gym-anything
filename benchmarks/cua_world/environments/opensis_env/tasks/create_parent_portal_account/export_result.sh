#!/bin/bash
set -e
echo "=== Exporting task results ==="

DB_USER="opensis_user"
DB_PASS="opensis_password_123"
DB_NAME="opensis"

# 1. Capture Final Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Get Task Info
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_PARENT_COUNT=$(cat /tmp/initial_parent_count.txt 2>/dev/null || echo "0")
KEVIN_ID=$(cat /tmp/kevin_id.txt 2>/dev/null || echo "0")

# 3. Query Database for Results

# A. Check if user 'mchen_parent' exists in login_authentication
# We fetch: user_id, profile_id, username, created_at (if available), password (hash)
USER_AUTH_JSON=$(mysql -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" -N -B -e "
    SELECT user_id, profile_id, username, password 
    FROM login_authentication 
    WHERE username='mchen_parent'" 2>/dev/null | \
    jq -R -s -c 'split("\n") | map(select(length>0)) | map(split("\t")) | map({user_id: .[0], profile_id: .[1], username: .[2], password_hash: .[3]}) | .[0] // null')

# B. Check for User Profile Details (Name)
# In OpenSIS, user details are often in 'staff' table linked by staff_id = user_id (or similar)
# We search for Margaret Chen in staff
USER_DETAILS_JSON=$(mysql -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" -N -B -e "
    SELECT staff_id, first_name, last_name, profile 
    FROM staff 
    WHERE first_name='Margaret' AND last_name='Chen'" 2>/dev/null | \
    jq -R -s -c 'split("\n") | map(select(length>0)) | map(split("\t")) | map({staff_id: .[0], first_name: .[1], last_name: .[2], profile: .[3]}) | .[0] // null')

# C. Check for Linkage to Student Kevin Chen
# Linkage tables vary by OpenSIS version. Common ones: students_join_users, student_contacts.
# We will query multiple potential tables and aggregate.

# Try 'students_join_users'
LINK_SJU_COUNT=$(mysql -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" -N -B -e "
    SELECT COUNT(*) 
    FROM students_join_users 
    WHERE student_id='$KEVIN_ID' AND staff_id IN (SELECT staff_id FROM staff WHERE first_name='Margaret' AND last_name='Chen')" 2>/dev/null || echo "0")

# Try 'student_contacts' (sometimes used for parents)
LINK_CONTACT_COUNT=$(mysql -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" -N -B -e "
    SELECT COUNT(*)
    FROM student_contacts
    WHERE student_id='$KEVIN_ID' AND first_name='Margaret' AND last_name='Chen'" 2>/dev/null || echo "0")

# D. Current Parent Count
CURRENT_PARENT_COUNT=$(mysql -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" -N -B -e "SELECT COUNT(*) FROM login_authentication WHERE profile_id=4" 2>/dev/null || echo "0")

# 4. Construct JSON Result
# Using a temp file to avoid permission issues with cat/redirection
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $TASK_START,
    "initial_parent_count": $INITIAL_PARENT_COUNT,
    "current_parent_count": $CURRENT_PARENT_COUNT,
    "user_auth": $USER_AUTH_JSON,
    "user_details": $USER_DETAILS_JSON,
    "linkage_counts": {
        "students_join_users": $LINK_SJU_COUNT,
        "student_contacts": $LINK_CONTACT_COUNT
    },
    "kevin_student_id": "$KEVIN_ID"
}
EOF

# Move to standard location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="