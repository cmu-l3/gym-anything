#!/bin/bash
set -e
echo "=== Exporting task results ==="

# 1. Capture Final Screenshot
echo "Capturing final state..."
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Database Credentials
DB_USER="opensis_user"
DB_PASS="opensis_password_123"
DB_NAME="opensis"
MYSQL_CMD="mysql -u $DB_USER -p$DB_PASS $DB_NAME"

# 3. Retrieve Task Context
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
STUDENT_ID=$(cat /tmp/target_student_id.txt 2>/dev/null || echo "0")

echo "Checking database for student ID: $STUDENT_ID"

# 4. Query Address Data
# We look in the 'address' table. In OpenSIS, address records are often linked 
# via 'students_join_address', or directly in 'address' with a student_id if simplified.
# We will dump relevant columns to JSON.

# Query strategy: Find address linked to this student ID
# Using JSON_OBJECT for cleaner export if MariaDB supports it, otherwise manual construction.
# We'll use manual construction to be safe with older MariaDB versions.

ADDRESS_DATA=$($MYSQL_CMD -N -B -e "
SELECT 
    a.address_id, 
    a.address, 
    a.city, 
    a.state, 
    a.zipcode, 
    a.phone,
    a.student_id
FROM address a 
LEFT JOIN students_join_address sja ON a.address_id = sja.address_id 
WHERE a.student_id = $STUDENT_ID OR sja.student_id = $STUDENT_ID
LIMIT 1;
" 2>/dev/null || echo "")

# If not found in address table, check if it's in the students table fields (legacy/alternate config)
if [ -z "$ADDRESS_DATA" ]; then
    STUDENT_DATA=$($MYSQL_CMD -N -B -e "
    SELECT 
        student_id, 
        street_address_1, 
        city, 
        state, 
        zipcode, 
        phone 
    FROM students 
    WHERE student_id = $STUDENT_ID
    " 2>/dev/null || echo "")
fi

# 5. Check if App is Running
APP_RUNNING=$(pgrep -f "chrome" > /dev/null && echo "true" || echo "false")

# 6. Parse SQL output into variables
# Default values
ADDR_FOUND="false"
ADDR_STREET=""
ADDR_CITY=""
ADDR_STATE=""
ADDR_ZIP=""
ADDR_PHONE=""
ADDR_ID="0"

if [ -n "$ADDRESS_DATA" ]; then
    ADDR_FOUND="true"
    # Parse tab-separated output
    ADDR_ID=$(echo "$ADDRESS_DATA" | cut -f1)
    ADDR_STREET=$(echo "$ADDRESS_DATA" | cut -f2)
    ADDR_CITY=$(echo "$ADDRESS_DATA" | cut -f3)
    ADDR_STATE=$(echo "$ADDRESS_DATA" | cut -f4)
    ADDR_ZIP=$(echo "$ADDRESS_DATA" | cut -f5)
    ADDR_PHONE=$(echo "$ADDRESS_DATA" | cut -f6)
elif [ -n "$STUDENT_DATA" ] && [ "$(echo "$STUDENT_DATA" | cut -f2)" != "NULL" ] && [ "$(echo "$STUDENT_DATA" | cut -f2)" != "" ]; then
    # Fallback to student table data
    ADDR_FOUND="true"
    ADDR_ID="student_record"
    ADDR_STREET=$(echo "$STUDENT_DATA" | cut -f2)
    ADDR_CITY=$(echo "$STUDENT_DATA" | cut -f3)
    ADDR_STATE=$(echo "$STUDENT_DATA" | cut -f4)
    ADDR_ZIP=$(echo "$STUDENT_DATA" | cut -f5)
    ADDR_PHONE=$(echo "$STUDENT_DATA" | cut -f6)
fi

# 7. Create JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_timestamp": $TASK_START,
    "student_id": $STUDENT_ID,
    "address_found": $ADDR_FOUND,
    "address_record": {
        "id": "$ADDR_ID",
        "street": "$(echo "$ADDR_STREET" | sed 's/"/\\"/g')",
        "city": "$(echo "$ADDR_CITY" | sed 's/"/\\"/g')",
        "state": "$(echo "$ADDR_STATE" | sed 's/"/\\"/g')",
        "zip": "$(echo "$ADDR_ZIP" | sed 's/"/\\"/g')",
        "phone": "$(echo "$ADDR_PHONE" | sed 's/"/\\"/g')"
    },
    "app_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# 8. Save to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="