#!/bin/bash
set -e
echo "=== Exporting Result ==="

# 1. Record end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 2. Database credentials
DB_USER="opensis_user"
DB_PASS="opensis_password_123"
DB_NAME="opensis"
MYSQL_CMD="mysql -u $DB_USER -p$DB_PASS $DB_NAME -N -B"

# 3. Find the student ID for Emily Blunt
STUDENT_ID=$($MYSQL_CMD -e "SELECT student_id FROM students WHERE first_name='Emily' AND last_name='Blunt' LIMIT 1;" || echo "")

if [ -z "$STUDENT_ID" ]; then
    echo "ERROR: Student Emily Blunt not found in database."
    # Create empty result for verifier to handle gracefully
    cat > /tmp/task_result.json << EOF
{
    "error": "Student not found"
}
EOF
    exit 0
fi

# 4. Export Student Data
# Get is_disable status (0=Active, 1=Inactive usually in OpenSIS legacy, but enrollment table is source of truth)
IS_DISABLE=$($MYSQL_CMD -e "SELECT is_disable FROM students WHERE student_id='$STUDENT_ID';")

# 5. Export Enrollment History
# We fetch all enrollment records for this student as a JSON array
# Columns: id, start_date, end_date, enroll_code, grade_level
# We construct a JSON string manually or use python if available. 
# Here we'll use a simple python one-liner to fetch and format to avoid bash JSON hell.

cat > /tmp/fetch_enrollment.py << PYEOF
import mysql.connector
import json
import datetime
import os

try:
    conn = mysql.connector.connect(
        user="$DB_USER", 
        password="$DB_PASS", 
        host="localhost", 
        database="$DB_NAME"
    )
    cursor = conn.cursor(dictionary=True)
    
    student_id = "$STUDENT_ID"
    
    # Get all enrollment records
    query = f"SELECT * FROM student_enrollment WHERE student_id = {student_id} ORDER BY start_date ASC"
    cursor.execute(query)
    rows = cursor.fetchall()
    
    # Handle date serialization
    def default(o):
        if isinstance(o, (datetime.date, datetime.datetime)):
            return o.isoformat()
        return str(o)

    # Get Enrollment Codes for lookup
    cursor.execute("SELECT id, title FROM enrollment_codes")
    codes = {row['id']: row['title'] for row in cursor.fetchall()}
    
    # Enrich rows with code titles
    for row in rows:
        eid = row.get('enroll_code')
        row['enroll_code_title'] = codes.get(eid, "Unknown")
        
    result = {
        "student_id": student_id,
        "enrollment_records": rows,
        "record_count": len(rows),
        "task_start_ts": $TASK_START,
        "task_end_ts": $TASK_END
    }
    
    print(json.dumps(result, default=default))
    
except Exception as e:
    print(json.dumps({"error": str(e)}))

finally:
    if 'conn' in locals() and conn.is_connected():
        conn.close()
PYEOF

# Execute python script and save result
python3 /tmp/fetch_enrollment.py > /tmp/task_result.json

# 6. Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true
echo "Final screenshot captured."

# 7. Permission fix
chmod 666 /tmp/task_result.json
echo "Result exported to /tmp/task_result.json"