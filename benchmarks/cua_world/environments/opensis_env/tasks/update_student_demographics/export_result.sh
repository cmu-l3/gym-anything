#!/bin/bash
set -e

echo "=== Exporting Update Student Demographics Result ==="

# 1. Capture Final Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Collect Data
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

DB_USER="opensis_user"
DB_PASS="opensis_password_123"
DB_NAME="opensis"

# Query the database for the student record as JSON
# We construct a JSON object manually from the query result to ensure valid JSON
# Using -B (batch/tab-separated) and -N (skip headers) for easy parsing

# Query: Get specific fields for student 100
QUERY="SELECT first_name, last_name, date_of_birth, address, city, state, zipcode, phone, email FROM students WHERE student_id=100"

RAW_DATA=$(mysql -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" -N -B -e "$QUERY" 2>/dev/null)

if [ -z "$RAW_DATA" ]; then
    FOUND="false"
    STUDENT_JSON="null"
else
    FOUND="true"
    # Parse tab-separated values into variables
    IFS=$'\t' read -r FNAME LNAME DOB ADDR CITY STATE ZIP PHONE EMAIL <<< "$RAW_DATA"
    
    # Construct JSON manually to handle potential special chars safely
    # (Basic escaping for quotes)
    FNAME=$(echo "$FNAME" | sed 's/"/\\"/g')
    ADDR=$(echo "$ADDR" | sed 's/"/\\"/g')
    CITY=$(echo "$CITY" | sed 's/"/\\"/g')
    
    STUDENT_JSON="{
        \"first_name\": \"$FNAME\",
        \"last_name\": \"$LNAME\",
        \"date_of_birth\": \"$DOB\",
        \"address\": \"$ADDR\",
        \"city\": \"$CITY\",
        \"state\": \"$STATE\",
        \"zipcode\": \"$ZIP\",
        \"phone\": \"$PHONE\",
        \"email\": \"$EMAIL\"
    }"
fi

# 3. Create Result JSON
# Use a temp file to avoid permission issues during creation
TEMP_JSON=$(mktemp /tmp/result_export.XXXXXX)

cat > "$TEMP_JSON" <<EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "student_found": $FOUND,
    "student_data": $STUDENT_JSON,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location
rm -f /tmp/task_result.json 2>/dev/null || true
mv "$TEMP_JSON" /tmp/task_result.json
chmod 644 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="