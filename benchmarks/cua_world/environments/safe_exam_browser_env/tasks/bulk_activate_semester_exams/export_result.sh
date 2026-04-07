#!/bin/bash
echo "=== Exporting bulk_activate_semester_exams result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Take final screenshot
take_screenshot /tmp/final_screenshot.png

# Query database for current state of exams
cat << 'PYEOF' > /tmp/export_exams.py
import json
import pymysql
import os
import time

result = {
    "timestamp": time.time(),
    "exams": {},
    "screenshot_exists": os.path.exists("/tmp/final_screenshot.png"),
    "error": None
}

try:
    conn = pymysql.connect(host='127.0.0.1', user='root', password='sebserver123', database='SEBServer')
    with conn.cursor(pymysql.cursors.DictCursor) as c:
        c.execute("SHOW COLUMNS FROM exam")
        cols = [r['Field'] for r in c.fetchall()]
        
        query_cols = ['name']
        if 'active' in cols: query_cols.append('active')
        if 'status' in cols: query_cols.append('status')
        
        col_str = ", ".join(query_cols)
        c.execute(f"SELECT {col_str} FROM exam WHERE name LIKE 'Spring 2026%%' OR name LIKE 'Fall 2025%%'")
        
        for row in c.fetchall():
            # Clean up un-serializable types for JSON (like tinyint/bytes)
            clean_row = {}
            for k, v in row.items():
                if isinstance(v, bytes):
                    clean_row[k] = v.decode('utf-8')
                else:
                    clean_row[k] = v
            result["exams"][row['name']] = clean_row
            
except Exception as e:
    result["error"] = str(e)

with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)

print(json.dumps(result, indent=2))
PYEOF

docker exec -i seb-server-mariadb python3 < /tmp/export_exams.py || python3 /tmp/export_exams.py || echo '{"error": "Failed to run export script"}' > /tmp/task_result.json

chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export complete ==="