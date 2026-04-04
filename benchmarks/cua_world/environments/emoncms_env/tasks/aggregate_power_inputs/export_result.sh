#!/bin/bash
# Export script for Aggregate Power Inputs task
set -e
echo "=== Exporting task results ==="

source /workspace/scripts/task_utils.sh

# Capture final screenshot
take_screenshot /tmp/task_final.png

# Capture timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Helper to run SQL and output JSON
# We use python inside the script to format the JSON reliably from SQL output
cat > /tmp/export_data.py << 'PYTHON_EOF'
import json
import subprocess
import sys

def db_query_json(query):
    cmd = [
        "docker", "exec", "emoncms-db", 
        "mysql", "-u", "emoncms", "-pemoncms", "emoncms", 
        "-B", "-e", query
    ]
    try:
        # -B gives tab separated output with headers
        result = subprocess.run(cmd, capture_output=True, text=True)
        if result.returncode != 0:
            return []
        
        lines = result.stdout.strip().split('\n')
        if not lines:
            return []
            
        headers = lines[0].split('\t')
        data = []
        for line in lines[1:]:
            values = line.split('\t')
            row = dict(zip(headers, values))
            data.append(row)
        return data
    except Exception as e:
        return []

# Fetch Inputs
inputs = db_query_json("SELECT id, name, nodeid, processList FROM inputs WHERE nodeid='site_meters'")

# Fetch Feeds
feeds = db_query_json("SELECT id, name, tag, datatype, engine FROM feeds")

# Output structure
output = {
    "inputs": inputs,
    "feeds": feeds,
    "task_start": int(sys.argv[1]),
    "task_end": int(sys.argv[2])
}

print(json.dumps(output, indent=2))
PYTHON_EOF

# Run the python script
python3 /tmp/export_data.py "$TASK_START" "$TASK_END" > /tmp/temp_result.json

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || true
cp /tmp/temp_result.json /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
echo "=== Export complete ==="