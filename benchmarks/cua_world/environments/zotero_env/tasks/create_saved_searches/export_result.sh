#!/bin/bash
echo "=== Exporting create_saved_searches result ==="

DB="/home/ga/Zotero/zotero.sqlite"
RESULT_FILE="/tmp/task_result.json"

# 1. Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Query Database for Saved Searches and their Conditions
# We construct a JSON object using python to handle the SQL query output cleanly
python3 << 'PYEOF'
import sqlite3
import json
import os
import time

db_path = "/home/ga/Zotero/zotero.sqlite"
result_file = "/tmp/task_result.json"
start_time_file = "/tmp/task_start_time.txt"

# Default result structure
output = {
    "task_start_ts": 0,
    "current_ts": time.time(),
    "saved_searches": [],
    "total_searches": 0,
    "app_running": False
}

# Get task start time
try:
    if os.path.exists(start_time_file):
        with open(start_time_file, 'r') as f:
            output["task_start_ts"] = int(f.read().strip())
except:
    pass

# Check if app is running
try:
    if os.system("pgrep -f zotero > /dev/null") == 0:
        output["app_running"] = True
except:
    pass

# Query Database
try:
    if os.path.exists(db_path):
        conn = sqlite3.connect(db_path)
        conn.row_factory = sqlite3.Row
        cur = conn.cursor()
        
        # Get all saved searches for user library (libraryID=1)
        # Zotero 7 schema: savedSearches (savedSearchID, savedSearchName, libraryID, ...)
        cur.execute("SELECT savedSearchID, savedSearchName FROM savedSearches WHERE libraryID=1")
        searches = cur.fetchall()
        
        output["total_searches"] = len(searches)
        
        for search in searches:
            s_obj = {
                "name": search["savedSearchName"],
                "id": search["savedSearchID"],
                "conditions": []
            }
            
            # Get conditions for this search
            # savedSearchConditions (savedSearchID, condition, operator, value)
            cur.execute("""
                SELECT condition, operator, value 
                FROM savedSearchConditions 
                WHERE savedSearchID = ?
            """, (search["savedSearchID"],))
            
            conditions = cur.fetchall()
            for cond in conditions:
                s_obj["conditions"].append({
                    "field": cond["condition"],
                    "operator": cond["operator"],
                    "value": cond["value"]
                })
            
            output["saved_searches"].append(s_obj)
            
        conn.close()
except Exception as e:
    output["error"] = str(e)

# Write result
with open(result_file, 'w') as f:
    json.dump(output, f, indent=2)
    
print(f"Exported {output['total_searches']} saved searches to {result_file}")
PYEOF

cat "$RESULT_FILE"
echo "=== Export complete ==="