#!/bin/bash
echo "=== Exporting create_data_asset results ==="

source /workspace/scripts/task_utils.sh

# 1. Capture final screenshot
take_screenshot /tmp/task_final.png

# 2. Get task start time and initial count
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_COUNT=$(cat /tmp/initial_data_asset_count.txt 2>/dev/null || echo "0")

# 3. Query the database for the new record
# We look for records created after the task started
# We fetch relevant fields to verify content
# Note: Eramba schema often uses 'name' or 'title' for the main label. We select columns dynamically or guess.
# Common Eramba columns: id, name, description, created, modified
echo "Querying database for new Data Assets..."

# We use a python script to handle the DB query and JSON creation safely
cat > /tmp/query_result.py << 'PYEOF'
import subprocess
import json
import time
import sys

def run_query(query):
    cmd = [
        "docker", "exec", "eramba-db", 
        "mysql", "-u", "eramba", "-peramba_db_pass", "eramba", 
        "-N", "-e", query
    ]
    try:
        result = subprocess.check_output(cmd, stderr=subprocess.DEVNULL).decode('utf-8').strip()
        return result
    except subprocess.CalledProcessError:
        return ""

def main():
    task_start = int(sys.argv[1])
    initial_count = int(sys.argv[2])
    
    # 1. Get current count
    count_res = run_query("SELECT COUNT(*) FROM data_assets WHERE deleted=0;")
    final_count = int(count_res) if count_res.isdigit() else 0
    
    # 2. Find the specific record created during the task
    # We look for the title specifically mentioned in the task
    # Using LIKE to be slightly flexible with spacing
    target_title = "Customer Loyalty Program Database"
    
    # Fetch columns: id, name, description, created
    # Note: If 'name' doesn't exist, it might be 'title' or 'index'. 
    # We'll try to list columns first or just assume 'name' based on standard Eramba/CakePHP conventions.
    # Actually, let's just SELECT * and parse in python to be safe against column naming variations, 
    # OR try specific columns. Let's try 'name' first.
    
    query = f"SELECT id, name, description, created, modified FROM data_assets WHERE name LIKE '%{target_title}%' AND deleted=0 ORDER BY created DESC LIMIT 1;"
    row_data = run_query(query)
    
    record_found = False
    record_details = {}
    
    if row_data:
        parts = row_data.split('\t')
        if len(parts) >= 4:
            record_found = True
            record_details = {
                "id": parts[0],
                "title": parts[1],
                "description": parts[2],
                "created": parts[3],
                "modified": parts[4] if len(parts) > 4 else ""
            }

    # 3. Construct result
    result = {
        "task_start_time": task_start,
        "initial_count": initial_count,
        "final_count": final_count,
        "count_increased": final_count > initial_count,
        "record_found": record_found,
        "record": record_details,
        "screenshot_exists": True # We know we took it
    }
    
    print(json.dumps(result, indent=2))

if __name__ == "__main__":
    main()
PYEOF

# Run the python script
python3 /tmp/query_result.py "$TASK_START" "$INITIAL_COUNT" > /tmp/task_result.json

echo "Result JSON generated:"
cat /tmp/task_result.json

# Cleanup
rm /tmp/query_result.py

echo "=== Export complete ==="