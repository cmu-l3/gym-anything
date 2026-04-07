#!/bin/bash
set -e
echo "=== Exporting results for: add_grade_levels ==="

# 1. Capture Final Screenshot
echo "Capturing final state..."
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Gather Data
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_COUNT=$(cat /tmp/initial_gl_count.txt 2>/dev/null || echo "0")

# 3. Query Database for Results
# We use Python to robustly query MySQL and format JSON to avoid bash string escaping hell
cat > /tmp/query_results.py << 'EOF'
import mysql.connector
import json
import time
import os
import sys

try:
    conn = mysql.connector.connect(
        user="opensis_user",
        password="opensis_password_123",
        database="opensis",
        host="localhost"
    )
    cursor = conn.cursor(dictionary=True)

    # Query 1: All grade levels with sort order
    cursor.execute("SELECT id, title, short_name, sort_order FROM school_gradelevels WHERE school_id = 1 ORDER BY sort_order ASC")
    all_grades = cursor.fetchall()

    # Query 2: Specific check for new grades
    cursor.execute("SELECT * FROM school_gradelevels WHERE school_id = 1 AND short_name IN ('7', '8', '07', '08')")
    new_grades = cursor.fetchall()

    # Query 3: Count total
    cursor.execute("SELECT COUNT(*) as count FROM school_gradelevels WHERE school_id = 1")
    count_res = cursor.fetchone()
    total_count = count_res['count']

    # Anti-gaming: Check if modification time roughly correlates (not perfect in MySQL 5.x/MariaDB without updated_at triggers, 
    # but we can rely on ID being higher than pre-existing max ID if auto-increment is used)
    # Getting max ID before task would have been better, but count diff is a good proxy.
    
    result = {
        "all_grades": all_grades,
        "new_grades": new_grades,
        "total_count": total_count,
        "success": True,
        "error": None
    }

except Exception as e:
    result = {
        "all_grades": [],
        "new_grades": [],
        "total_count": 0,
        "success": False,
        "error": str(e)
    }
finally:
    if 'conn' in locals() and conn.is_connected():
        cursor.close()
        conn.close()

# Read bash variables passed via env or files if needed, but here we just print the db result
print(json.dumps(result))
EOF

# Execute python script
DB_JSON=$(python3 /tmp/query_results.py)

# 4. Construct Final JSON
# Combine DB results with environment stats
cat > /tmp/task_result.json << EOF
{
    "task_start_timestamp": $TASK_START,
    "initial_grade_count": $INITIAL_COUNT,
    "db_results": $DB_JSON,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# 5. Set Permissions so Verifier can read it
chmod 644 /tmp/task_result.json

echo "Export complete. Result saved to /tmp/task_result.json"