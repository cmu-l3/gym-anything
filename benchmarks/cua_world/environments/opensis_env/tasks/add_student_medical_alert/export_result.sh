#!/bin/bash
echo "=== Exporting task results ==="

# Database credentials
DB_USER="opensis_user"
DB_PASS="opensis_password_123"
DB_NAME="opensis"

# Timestamps
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Final Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Get Student ID
STUDENT_ID=$(mysql -N -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" -e "SELECT student_id FROM students WHERE first_name='Sarah' AND last_name='Connor' LIMIT 1" 2>/dev/null)

# Get Medical Records
# We select relevant columns. Using 'IFNULL' to handle schema variations safely in SQL would be complex,
# so we assume standard columns: medical_id, student_id, title/code, comments/description, medical_date
echo "Querying medical records..."
RECORDS_JSON="[]"

if [ -n "$STUDENT_ID" ]; then
    # Try to detect table structure or just query likely columns
    # We query specific columns and format as JSON using jq if available, or manual construction
    # Here we construct a simple JSON array manually from tab-separated output
    
    # Check if table is 'student_medical' or 'medical_records'
    TABLE_NAME="student_medical"
    if ! mysql -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" -e "SELECT 1 FROM student_medical LIMIT 1" 2>/dev/null; then
        TABLE_NAME="medical_records" # Fallback guess
    fi
    
    # Query data
    # Note: Column names might vary (comments vs description). We select * to be safe and parse in python,
    # or try to concatenate common fields.
    RAW_DATA=$(mysql -N -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" -e "SELECT CONCAT(IFNULL(title,''), ' ', IFNULL(comments,''), ' ', IFNULL(code,'')) as content, medical_date FROM $TABLE_NAME WHERE student_id=$STUDENT_ID" 2>/dev/null)
    
    # Build JSON array
    RECORDS_JSON="["
    while IFS=$'\t' read -r content date; do
        # escape quotes
        safe_content=$(echo "$content" | sed 's/"/\\"/g' | tr -d '\n')
        safe_date=$(echo "$date" | sed 's/"/\\"/g')
        RECORDS_JSON="$RECORDS_JSON {\"content\": \"$safe_content\", \"date\": \"$safe_date\"},"
    done <<< "$RAW_DATA"
    
    # Remove trailing comma and close array
    RECORDS_JSON="${RECORDS_JSON%,}]"
fi

# Initial Count
INITIAL_COUNT=$(cat /tmp/initial_medical_count.txt 2>/dev/null || echo "0")

# Write result JSON
cat > /tmp/task_result.json <<EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "student_id": "${STUDENT_ID:-0}",
    "initial_count": $INITIAL_COUNT,
    "medical_records": $RECORDS_JSON,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Ensure permissions
chmod 666 /tmp/task_result.json

echo "Export complete. Result:"
cat /tmp/task_result.json