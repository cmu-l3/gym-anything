#!/bin/bash
echo "=== Exporting task results ==="

# Record task end time
TASK_END=$(date +%s)

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Extract comprehensive information via Python
# This directly builds the JSON to make the host verifier simpler
python3 << 'EOF'
import csv
import json
import os
import sys
import re

res = {
    "output_exists": False,
    "file_created_during_task": False,
    "output_size_bytes": 0,
    "valid_csv": False,
    "headers": [],
    "row_count": 0,
    "first_time": "",
    "first_val": "",
    "last_time": "",
    "last_val": "",
    "script_created": False,
    "error": ""
}

task_start = 0
try:
    with open("/tmp/task_start_time.txt", "r") as f:
        task_start = int(f.read().strip())
except Exception:
    pass

# Check if the agent created a Python script to do the work
for file in os.listdir("/home/ga"):
    if file.endswith(".py"):
        p = os.path.join("/home/ga", file)
        if os.path.getmtime(p) > task_start:
            res["script_created"] = True
            break

output_path = "/home/ga/toli_waveform.csv"

if os.path.exists(output_path):
    res["output_exists"] = True
    mtime = os.path.getmtime(output_path)
    res["output_size_bytes"] = os.path.getsize(output_path)
    res["file_created_during_task"] = mtime > task_start
    
    try:
        with open(output_path, "r", encoding="utf-8", errors="replace") as f:
            reader = csv.reader(f)
            headers = next(reader, None)
            if headers:
                res["headers"] = [h.strip() for h in headers]
            
            rows = list(reader)
            # Filter out empty rows
            rows = [r for r in rows if len(r) > 0 and any(x.strip() for x in r)]
            res["row_count"] = len(rows)
            
            if rows:
                res["first_time"] = rows[0][0] if len(rows[0]) > 0 else ""
                res["first_val"] = rows[0][1] if len(rows[0]) > 1 else ""
                res["last_time"] = rows[-1][0] if len(rows[-1]) > 0 else ""
                res["last_val"] = rows[-1][1] if len(rows[-1]) > 1 else ""
                
        res["valid_csv"] = True
    except Exception as e:
        res["error"] = str(e)

# Write result securely
try:
    with open("/tmp/task_result.json", "w") as f:
        json.dump(res, f, indent=4)
except Exception as e:
    print(f"Error writing json: {e}")
EOF

chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="