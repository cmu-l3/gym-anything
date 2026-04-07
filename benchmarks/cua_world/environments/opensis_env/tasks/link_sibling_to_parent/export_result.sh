#!/bin/bash
set -e

echo "=== Exporting task results ==="

DB_USER="opensis_user"
DB_PASS="opensis_password_123"
DB_NAME="opensis"
MYSQL_CMD="mysql -u $DB_USER -p$DB_PASS $DB_NAME -N -e"

# 1. Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Get IDs again to be sure
DASH_ID=$($MYSQL_CMD "SELECT student_id FROM students WHERE first_name='Dash' AND last_name='Parr' LIMIT 1;" 2>/dev/null || echo "0")
ROBERT_ID=$($MYSQL_CMD "SELECT student_id FROM students WHERE first_name='Robert' AND last_name='Parr' ORDER BY student_id ASC LIMIT 1;" 2>/dev/null || echo "0")

# 3. Check if Dash is linked to Robert
# We look for a record in student_parent connecting Dash's ID to Robert's ID
LINK_EXISTS="false"
if [ "$DASH_ID" != "0" ] && [ "$ROBERT_ID" != "0" ]; then
    LINK_COUNT=$($MYSQL_CMD "SELECT COUNT(*) FROM student_parent WHERE student_id=$DASH_ID AND parent_id=$ROBERT_ID;" 2>/dev/null || echo "0")
    if [ "$LINK_COUNT" -ge 1 ]; then
        LINK_EXISTS="true"
    fi
fi

# 4. Check for duplicates (Anti-gaming)
# If the agent created a NEW Robert Parr, there will be more than 1 record in 'students' table matching name
CURRENT_PARENT_COUNT=$($MYSQL_CMD "SELECT COUNT(*) FROM students WHERE first_name='Robert' AND last_name='Parr';" 2>/dev/null || echo "0")
INITIAL_PARENT_COUNT=$(cat /tmp/initial_parent_count.txt 2>/dev/null || echo "1")

DUPLICATE_CREATED="false"
if [ "$CURRENT_PARENT_COUNT" -gt "$INITIAL_PARENT_COUNT" ]; then
    DUPLICATE_CREATED="true"
fi

# 5. Check if Dash has ANY parent linked (even if wrong one)
TOTAL_LINKS_DASH=$($MYSQL_CMD "SELECT COUNT(*) FROM student_parent WHERE student_id=$DASH_ID;" 2>/dev/null || echo "0")

# 6. Verify Robert is linked to BOTH children
TOTAL_KIDS_ROBERT=$($MYSQL_CMD "SELECT COUNT(*) FROM student_parent WHERE parent_id=$ROBERT_ID;" 2>/dev/null || echo "0")

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "link_exists": $LINK_EXISTS,
    "duplicate_created": $DUPLICATE_CREATED,
    "initial_parent_count": $INITIAL_PARENT_COUNT,
    "current_parent_count": $CURRENT_PARENT_COUNT,
    "dash_parent_link_count": $TOTAL_LINKS_DASH,
    "robert_children_count": $TOTAL_KIDS_ROBERT,
    "target_parent_id": $ROBERT_ID,
    "target_student_id": $DASH_ID,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="