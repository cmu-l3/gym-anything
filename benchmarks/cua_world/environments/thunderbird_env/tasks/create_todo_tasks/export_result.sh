#!/bin/bash
set -e
echo "=== Exporting create_todo_tasks results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Extract start time
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Check if Thunderbird is running
APP_RUNNING=$(pgrep -f "thunderbird" > /dev/null && echo "true" || echo "false")

# Query calendar database safely and export to JSON
# We use a python script to avoid sqlite locking issues and parse data neatly
python3 << EOF
import sqlite3
import json
import os

db_path = "/home/ga/.thunderbird/default-release/calendar-data/local.sqlite"
todos = []

if os.path.exists(db_path):
    try:
        # Open in read-only mode to prevent lock issues
        uri = f"file:{db_path}?mode=ro"
        conn = sqlite3.connect(uri, uri=True)
        conn.row_factory = sqlite3.Row
        cur = conn.cursor()
        
        # Select relevant fields
        cur.execute("""
            SELECT title, priority, todo_due, time_created 
            FROM cal_todos
        """)
        
        for row in cur.fetchall():
            todos.append({
                "title": row["title"],
                "priority": row["priority"],
                "todo_due": row["todo_due"],
                "time_created": row["time_created"]
            })
            
        conn.close()
    except Exception as e:
        print(f"Database query error: {e}")

result = {
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_running": $APP_RUNNING,
    "todos": todos
}

temp_file = "/tmp/result.temp.json"
with open(temp_file, "w") as f:
    json.dump(result, f)
EOF

# Move to final destination and set permissions
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp /tmp/result.temp.json /tmp/task_result.json 2>/dev/null || sudo cp /tmp/result.temp.json /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f /tmp/result.temp.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="