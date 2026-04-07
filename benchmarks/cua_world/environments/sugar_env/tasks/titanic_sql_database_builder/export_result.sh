#!/bin/bash
echo "=== Exporting titanic_sql_database_builder task result ==="

SUGAR_ENV="DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus"

# Take final screenshot
su - ga -c "$SUGAR_ENV scrot /tmp/titanic_task_end.png" 2>/dev/null || true

# Record timestamps
TASK_START=$(cat /tmp/titanic_task_start_ts 2>/dev/null || echo "0")
DB_PATH="/home/ga/Documents/titanic.db"
TXT_PATH="/home/ga/Documents/survival_summary.txt"

# Run a Python script to safely inspect the SQLite database and output text
python3 << 'PYEOF' > /tmp/titanic_result_raw.json 2>/dev/null || echo '{"error": "Export script failed"}' > /tmp/titanic_result_raw.json
import sqlite3
import json
import os
import stat

result = {
    "db_exists": False,
    "db_modified": False,
    "table_exists": False,
    "row_count": 0,
    "parse_correct": False,
    "txt_exists": False,
    "txt_modified": False,
    "summary_text": "",
    "error": None
}

db_path = "/home/ga/Documents/titanic.db"
txt_path = "/home/ga/Documents/survival_summary.txt"

try:
    with open('/tmp/titanic_task_start_ts', 'r') as f:
        task_start = int(f.read().strip())
except:
    task_start = 0

# Check DB
if os.path.exists(db_path):
    result["db_exists"] = True
    mtime = os.stat(db_path).st_mtime
    if mtime > task_start:
        result["db_modified"] = True
        
    try:
        conn = sqlite3.connect(db_path)
        c = conn.cursor()
        
        # Check if passengers table exists
        c.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='passengers'")
        if c.fetchone():
            result["table_exists"] = True
            
            # Count rows
            c.execute("SELECT count(*) FROM passengers")
            result["row_count"] = c.fetchone()[0]
            
            # Check for proper CSV parsing (naive comma split ruins columns)
            # Find a known row with a comma in the name, e.g., PassengerId=2 or 3
            # We'll just check if any row has 'female' in a column that makes sense, 
            # and that it didn't split names improperly.
            c.execute("PRAGMA table_info(passengers)")
            columns = [col[1].lower() for col in c.fetchall()]
            
            if 'sex' in columns:
                c.execute("SELECT sex FROM passengers LIMIT 20")
                sex_values = [str(row[0]).strip().lower() for row in c.fetchall()]
                # If parsed correctly, sex_values should contain pure 'male' or 'female'
                # If parsed naively with split(','), quotes remain or it shifts to the name fragment
                if 'female' in sex_values or 'male' in sex_values:
                    result["parse_correct"] = True
            else:
                # Fallback: check if the string 'female' is correctly isolated in any column
                c.execute("SELECT * FROM passengers LIMIT 20")
                for row in c.fetchall():
                    if 'female' in [str(x).strip().lower() for x in row]:
                        result["parse_correct"] = True
                        break

        conn.close()
    except Exception as e:
        result["error"] = f"DB Error: {str(e)}"

# Check Summary Text
if os.path.exists(txt_path):
    result["txt_exists"] = True
    mtime = os.stat(txt_path).st_mtime
    if mtime > task_start:
        result["txt_modified"] = True
        
    try:
        with open(txt_path, 'r', errors='ignore') as f:
            result["summary_text"] = f.read(1024)  # Read up to 1KB
    except Exception as e:
        if not result["error"]:
            result["error"] = f"Txt Error: {str(e)}"

print(json.dumps(result))
PYEOF

chmod 666 /tmp/titanic_result_raw.json
cp /tmp/titanic_result_raw.json /tmp/titanic_sql_result.json

echo "Result saved to /tmp/titanic_sql_result.json"
cat /tmp/titanic_sql_result.json
echo "=== Export complete ==="