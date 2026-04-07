#!/bin/bash
echo "=== Exporting task results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Database credentials
DB_USER="opensis_user"
DB_PASS="opensis_password_123"
DB_NAME="opensis"

# Output file
RESULT_JSON="/tmp/task_result.json"

# Capture final screenshot
echo "Capturing final screenshot..."
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# ==============================================================================
# VERIFICATION LOGIC
# ==============================================================================

# We need to find the record in the database.
# OpenSIS stores historical grades in 'student_mp_grades' or related history tables.
# We will query specifically for the student and the course 'Biology'.

# Get Student ID again
STUDENT_ID=$(mysql -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" -N -e "SELECT student_id FROM students WHERE first_name='Leo' AND last_name='Vance' LIMIT 1")

echo "Searching for Biology grade for Student ID: $STUDENT_ID..."

# Query to find the grade record
# We check common columns for course title and grade
# Note: course_name is often empty for historical entries in some OpenSIS versions, 
# storing the name in comments or a joined course table. 
# However, manual transcript entry usually populates 'course_name' text field in history tables.

QUERY="
SELECT 
    grade_id, 
    student_id, 
    course_name, 
    grade_percent, 
    grade_letter, 
    credit_attempted,
    credit_earned,
    syear
FROM student_mp_grades 
WHERE student_id = '$STUDENT_ID' 
AND (course_name LIKE '%Biology%' OR comment LIKE '%Biology%')
LIMIT 1
"

# Execute Query (output as tab-separated)
RAW_RESULT=$(mysql -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" -N -B -e "$QUERY" 2>/dev/null)

# Prepare JSON fields
FOUND="false"
COURSE=""
GRADE_VAL=""
CREDIT=""
YEAR=""

if [ -n "$RAW_RESULT" ]; then
    FOUND="true"
    # Parse the tab separated line
    # grade_id, student_id, course_name, grade_percent, grade_letter, credit_attempted, credit_earned, syear
    IFS=$'\t' read -r G_ID S_ID C_NAME G_PERCENT G_LETTER C_ATT C_EARN SYEAR <<< "$RAW_RESULT"
    
    COURSE="$C_NAME"
    GRADE_VAL="$G_PERCENT"
    CREDIT="$C_EARN"
    YEAR="$SYEAR"
else
    # Fallback: Check 'student_report_card_grades' if not found in mp_grades
    # Some installations use different tables for history vs current
    QUERY_ALT="
    SELECT 
        id, 
        student_id, 
        course_name, 
        grade_percent, 
        grade_letter, 
        credit,
        syear
    FROM student_report_card_grades
    WHERE student_id = '$STUDENT_ID' 
    AND course_name LIKE '%Biology%'
    LIMIT 1
    "
    RAW_RESULT_ALT=$(mysql -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" -N -B -e "$QUERY_ALT" 2>/dev/null)
    
    if [ -n "$RAW_RESULT_ALT" ]; then
        FOUND="true"
        IFS=$'\t' read -r G_ID S_ID C_NAME G_PERCENT G_LETTER C_EARN SYEAR <<< "$RAW_RESULT_ALT"
        COURSE="$C_NAME"
        GRADE_VAL="$G_PERCENT"
        CREDIT="$C_EARN"
        YEAR="$SYEAR"
    fi
fi

# Sanitize output for JSON (escape quotes)
COURSE=$(echo "$COURSE" | sed 's/"/\\"/g')

# Create JSON
# Note: We rely on the fact that we deleted previous records in setup_task.sh
# So if a record exists now, it must have been created by the agent.
# OpenSIS timestamps on grade tables aren't always reliable/present, so existence + diff is key.

cat > "$RESULT_JSON" <<EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "student_found": true,
    "record_found": $FOUND,
    "record_details": {
        "course_name": "$COURSE",
        "grade_percent": "$GRADE_VAL",
        "credit": "$CREDIT",
        "school_year": "$YEAR"
    },
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Ensure permissions
chmod 666 "$RESULT_JSON"

echo "Export complete. Result:"
cat "$RESULT_JSON"