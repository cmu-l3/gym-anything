#!/bin/bash
echo "=== Exporting task results ==="

# Record end state timing
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot to capture end state of the browser
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Dump the SQLite database records into a JSON file for the verifier
cat > /tmp/dump_db.py << 'EOF'
import sqlite3
import json
import os

db_path = '/var/lib/app/telemetry.db'
result = {"requests": []}

if os.path.exists(db_path):
    try:
        conn = sqlite3.connect(db_path)
        conn.row_factory = sqlite3.Row
        c = conn.cursor()
        c.execute("SELECT id, timestamp, method, path, payload, user_agent, status_code FROM requests ORDER BY id ASC")
        rows = c.fetchall()
        result["requests"] = [dict(row) for row in rows]
        conn.close()
    except Exception as e:
        result["error"] = str(e)
else:
    result["error"] = "Database not found."

with open('/tmp/task_result_temp.json', 'w') as f:
    json.dump(result, f, indent=4)
EOF

python3 /tmp/dump_db.py

# Safely copy to the final location to ensure it's readable by the framework
rm -f /tmp/task_result.json 2>/dev/null || true
cp /tmp/task_result_temp.json /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result JSON written to /tmp/task_result.json"
cat /tmp/task_result.json

echo "=== Export complete ==="