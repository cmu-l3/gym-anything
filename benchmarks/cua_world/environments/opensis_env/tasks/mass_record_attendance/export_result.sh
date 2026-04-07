#!/bin/bash
echo "=== Exporting Mass Attendance Results ==="

# Record end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TODAY=$(date +%Y-%m-%d)

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Use Python to verify database state and generate JSON result
# This handles the logic more cleanly than bash for complex JSON
cat > /tmp/verify_db.py << 'PYEOF'
import json
import pymysql
import sys
import datetime

db_config = {
    'host': 'localhost',
    'user': 'opensis_user',
    'password': 'opensis_password_123',
    'db': 'opensis',
    'cursorclass': pymysql.cursors.DictCursor
}

def get_attendance_stats():
    try:
        conn = pymysql.connect(**db_config)
        with conn.cursor() as cursor:
            # 1. Get IDs for Grade 12 (Target)
            cursor.execute("SELECT student_id FROM students WHERE grade_level = '12' AND is_active='Y'")
            g12_ids = [row['student_id'] for row in cursor.fetchall()]
            
            # 2. Get IDs for Grade 9 (Control)
            cursor.execute("SELECT student_id FROM students WHERE grade_level = '9' AND is_active='Y'")
            g9_ids = [row['student_id'] for row in cursor.fetchall()]
            
            # 3. Get Excused Code ID
            cursor.execute("SELECT id, title, short_name FROM attendance_codes WHERE title='Excused' OR short_name='E' LIMIT 1")
            code_row = cursor.fetchone()
            excused_code_id = code_row['id'] if code_row else None
            excused_title = code_row['title'] if code_row else "Unknown"
            
            # 4. Check Attendance for Target Group (Grade 12)
            # Checking attendance_period table which OpenSIS usually uses for daily/period attendance
            target_marked_correctly = 0
            if g12_ids:
                format_ids = ','.join(map(str, g12_ids))
                # Note: Schema varies, checking common pattern. Usually attendance_period or attendance_day.
                # We'll check for any record for today with the excused code
                query = f"""
                    SELECT COUNT(DISTINCT student_id) as count 
                    FROM attendance_period 
                    WHERE student_id IN ({format_ids}) 
                    AND school_date = CURDATE() 
                    AND attendance_code = %s
                """
                cursor.execute(query, (excused_code_id,))
                target_marked_correctly = cursor.fetchone()['count']
            
            # 5. Check Attendance for Control Group (Grade 9)
            # Should have 0 records (or at least 0 records created today)
            control_affected = 0
            if g9_ids:
                format_ids = ','.join(map(str, g9_ids))
                query = f"""
                    SELECT COUNT(DISTINCT student_id) as count 
                    FROM attendance_period 
                    WHERE student_id IN ({format_ids}) 
                    AND school_date = CURDATE()
                """
                cursor.execute(query)
                control_affected = cursor.fetchone()['count']

            return {
                "success": True,
                "total_g12": len(g12_ids),
                "marked_g12": target_marked_correctly,
                "total_g9": len(g9_ids),
                "affected_g9": control_affected,
                "excused_code_found": excused_code_id is not None,
                "excused_code_title": excused_title
            }
            
    except Exception as e:
        return {"success": False, "error": str(e)}
    finally:
        if 'conn' in locals():
            conn.close()

results = get_attendance_stats()
print(json.dumps(results))
PYEOF

# Execute Python script and save output
python3 /tmp/verify_db.py > /tmp/db_verification.json

# Combine into final result
cat > /tmp/combine_json.py << PYEOF
import json
import sys
import time

try:
    with open('/tmp/db_verification.json', 'r') as f:
        db_res = json.load(f)
except:
    db_res = {"success": False, "error": "Failed to read python output"}

final_res = {
    "task_start": int(sys.argv[1]),
    "task_end": int(time.time()),
    "db_check": db_res,
    "screenshot_exists": True  # We took one earlier
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(final_res, f)
PYEOF

python3 /tmp/combine_json.py "$TASK_START"

# Fix permissions
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"
echo "=== Export Complete ==="