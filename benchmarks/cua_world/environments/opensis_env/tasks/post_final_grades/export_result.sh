#!/bin/bash
set -e

echo "=== Exporting post_final_grades results ==="

DB_USER="opensis_user"
DB_PASS="opensis_password_123"
DB_NAME="opensis"

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Get task start time
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Query the grades
# We join students, schedule (to get course info), and student_report_card_grades
# Output as JSON using a python script for safety/formatting

python3 -c "
import mysql.connector
import json
import time
import sys

try:
    conn = mysql.connector.connect(
        user='$DB_USER',
        password='$DB_PASS',
        database='$DB_NAME',
        host='localhost'
    )
    cursor = conn.cursor(dictionary=True)

    # Query for the specific students and course
    query = \"\"\"
    SELECT 
        s.first_name, 
        s.last_name, 
        g.grade_percent, 
        g.grade_letter, 
        g.comment,
        g.course_period_id
    FROM student_report_card_grades g
    JOIN students s ON g.student_id = s.student_id
    JOIN course_periods cp ON g.course_period_id = cp.course_period_id
    JOIN courses c ON cp.course_id = c.course_id
    WHERE c.title = 'World History'
      AND s.first_name IN ('James', 'Sarah', 'Robert')
    \"\"\"
    
    cursor.execute(query)
    rows = cursor.fetchall()
    
    # Simple check if DB was modified recently (OpenSIS might not store updated_at in this table, 
    # but presence of records that were deleted in setup is the signal)
    
    result = {
        'grades': rows,
        'record_count': len(rows),
        'task_start': $TASK_START,
        'timestamp': time.time()
    }
    
    with open('/tmp/task_result.json', 'w') as f:
        json.dump(result, f, indent=2)
        
    print('Exported ' + str(len(rows)) + ' grade records.')

except Exception as e:
    print('Error: ' + str(e))
    # Write empty result on error
    with open('/tmp/task_result.json', 'w') as f:
        json.dump({'error': str(e)}, f)

finally:
    if 'conn' in locals() and conn.is_connected():
        conn.close()
"

# Set permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export complete ==="