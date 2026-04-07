#!/bin/bash
echo "=== Exporting task results ==="

# 1. Basic Metadata
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_GRADE_ID=$(cat /tmp/initial_grade_id.txt 2>/dev/null || echo "1")

DB_USER="opensis_user"
DB_PASS="opensis_password_123"
DB_NAME="opensis"

# 2. Query Final Database State
# We need to fetch:
# - If student exists
# - Current grade_id in enrollment
# - Current grade_level string in students table (sometimes OpenSIS updates both)
# - If student is still active (end_date is NULL)

SQL_QUERY="SELECT 
    s.student_id, 
    s.first_name, 
    s.last_name, 
    se.grade_id, 
    gl.title as grade_title,
    se.end_date 
FROM students s 
JOIN student_enrollment se ON s.student_id = se.student_id 
LEFT JOIN school_gradelevels gl ON se.grade_id = gl.id
WHERE s.student_id = 101 
LIMIT 1;"

# Execute Query and format as JSON manually to ensure no dependencies
# Using tab separation for easier parsing
DB_RESULT=$(sudo mysql -N -B -u $DB_USER -p"$DB_PASS" $DB_NAME -e "$SQL_QUERY" 2>/dev/null || echo "")

# Parse Result
# Format: student_id \t first \t last \t grade_id \t grade_title \t end_date
if [ -n "$DB_RESULT" ]; then
    STUDENT_EXISTS="true"
    STUDENT_ID=$(echo "$DB_RESULT" | cut -f1)
    FIRST_NAME=$(echo "$DB_RESULT" | cut -f2)
    LAST_NAME=$(echo "$DB_RESULT" | cut -f3)
    CURRENT_GRADE_ID=$(echo "$DB_RESULT" | cut -f4)
    CURRENT_GRADE_TITLE=$(echo "$DB_RESULT" | cut -f5)
    END_DATE=$(echo "$DB_RESULT" | cut -f6)
    
    # Check if enrolled (end_date should be NULL or empty)
    if [ "$END_DATE" == "NULL" ] || [ -z "$END_DATE" ]; then
        IS_ENROLLED="true"
    else
        IS_ENROLLED="false"
    fi
else
    STUDENT_EXISTS="false"
    STUDENT_ID="null"
    FIRST_NAME="null"
    LAST_NAME="null"
    CURRENT_GRADE_ID="null"
    CURRENT_GRADE_TITLE="null"
    IS_ENROLLED="false"
fi

# 3. Take Final Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 4. Generate JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "initial_grade_id": $INITIAL_GRADE_ID,
    "student_exists": $STUDENT_EXISTS,
    "student_info": {
        "id": "$STUDENT_ID",
        "first_name": "$FIRST_NAME",
        "last_name": "$LAST_NAME"
    },
    "enrollment": {
        "current_grade_id": "$CURRENT_GRADE_ID",
        "current_grade_title": "$CURRENT_GRADE_TITLE",
        "is_active": $IS_ENROLLED
    },
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location with read permissions
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="