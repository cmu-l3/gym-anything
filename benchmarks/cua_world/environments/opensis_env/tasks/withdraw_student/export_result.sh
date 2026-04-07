#!/bin/bash
set -e
echo "=== Exporting Withdraw Student Result ==="

# Record end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Database connection
DB_USER="opensis_user"
DB_PASS="opensis_password_123"
DB_NAME="opensis"
MYSQL_CMD="mysql -u $DB_USER -p$DB_PASS $DB_NAME -N -B"

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# ============================================================================
# DATA EXTRACTION
# ============================================================================

# We need to fetch the current enrollment status of Maria Rodriguez (Student ID 990)
# We join with student_enrollment_codes to get the text title of the drop code
QUERY="
SELECT 
    se.end_date,
    se.drop_code,
    sec.title as drop_code_title,
    se.last_updated
FROM student_enrollment se
LEFT JOIN student_enrollment_codes sec ON se.drop_code = sec.id
WHERE se.student_id = 990 AND se.syear = 2025
LIMIT 1;
"

# Execute query
# Output format: tab-separated values
# end_date | drop_code | drop_code_title | last_updated
RESULT_LINE=$($MYSQL_CMD -e "$QUERY" 2>/dev/null || echo "")

echo "Raw DB Result: $RESULT_LINE"

# Parse results using awk/cut
# If fields are NULL, mysql -B outputs literal "NULL" or empty strings depending on config
# We handle empty vars in Python verifier, just extract strings here

END_DATE=$(echo "$RESULT_LINE" | cut -f1)
DROP_CODE_ID=$(echo "$RESULT_LINE" | cut -f2)
DROP_CODE_TITLE=$(echo "$RESULT_LINE" | cut -f3)
LAST_UPDATED=$(echo "$RESULT_LINE" | cut -f4)

# Create JSON result
# Use a temp file to avoid permission issues
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)

cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "student_id": 990,
    "end_date": "$END_DATE",
    "drop_code_id": "$DROP_CODE_ID",
    "drop_code_title": "$DROP_CODE_TITLE",
    "last_updated": "$LAST_UPDATED",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="