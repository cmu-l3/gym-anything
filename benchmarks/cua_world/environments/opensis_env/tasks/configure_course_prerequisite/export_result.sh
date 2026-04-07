#!/bin/bash
set -e

echo "=== Exporting Configure Course Prerequisite results ==="

# 1. Capture Final Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Database Verification
DB_USER="opensis_user"
DB_PASS="opensis_password_123"
DB_NAME="opensis"
MYSQL_CMD="mysql -u $DB_USER -p$DB_PASS $DB_NAME -N -B -e"

# Get IDs again
ID_BIO=$($MYSQL_CMD "SELECT course_id FROM courses WHERE course_code='BIO101' LIMIT 1")
ID_ANATOMY=$($MYSQL_CMD "SELECT course_id FROM courses WHERE course_code='BIO201' LIMIT 1")

# Get Initial Count
INITIAL_COUNT=$(cat /tmp/initial_prereq_count.txt 2>/dev/null || echo "0")

# Query current prerequisites for Anatomy
# We select the req_course_id to see WHICH course was added
REQ_COURSE_IDS=$($MYSQL_CMD "SELECT req_course_id FROM course_reqs WHERE course_id='$ID_ANATOMY'" 2>/dev/null || echo "")

# Count current reqs
CURRENT_COUNT=$($MYSQL_CMD "SELECT COUNT(*) FROM course_reqs WHERE course_id='$ID_ANATOMY'" 2>/dev/null || echo "0")

# Check if BIO101 is specifically in the requirements
IS_BIO_LINKED="false"
if [ -n "$REQ_COURSE_IDS" ] && [ -n "$ID_BIO" ]; then
    for req_id in $REQ_COURSE_IDS; do
        if [ "$req_id" == "$ID_BIO" ]; then
            IS_BIO_LINKED="true"
        fi
    done
fi

# Get timestamp info if available (some opensis tables have updated_at, but course_reqs might not)
# We rely on the state change from 0 to >0 during the task window.

# 3. Create JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "initial_count": $INITIAL_COUNT,
    "current_count": $CURRENT_COUNT,
    "target_course_id": "$ID_ANATOMY",
    "required_course_id": "$ID_BIO",
    "found_req_ids": "$REQ_COURSE_IDS",
    "is_correct_prereq_linked": $IS_BIO_LINKED,
    "task_start_time": $(cat /tmp/task_start_time.txt 2>/dev/null || echo "0"),
    "export_time": $(date +%s),
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# 4. Safe Copy
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json