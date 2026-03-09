#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Exporting task results ==="

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Extract Data from Emoncms Database
# We need:
# - The processList for the 'greenhouse_temp' input
# - The table of feeds to verify names, engines, and intervals

# Create a temporary python script to fetch and format the data as JSON
# This runs on the host (container environment) and connects to the DB container
cat > /tmp/extract_data.py << 'EOF'
import subprocess
import json
import sys

def run_sql(query):
    cmd = [
        "docker", "exec", "emoncms-db", 
        "mysql", "-u", "emoncms", "-pemoncms", "emoncms", 
        "-N", "-e", query
    ]
    result = subprocess.run(cmd, capture_output=True, text=True)
    return result.stdout.strip()

data = {}

# Get Input Process List
# Returns: id \t processList
sql_input = "SELECT id, processList FROM inputs WHERE name='greenhouse_temp' LIMIT 1"
input_res = run_sql(sql_input)
if input_res:
    parts = input_res.split('\t')
    data['input_id'] = parts[0]
    data['process_list_str'] = parts[1] if len(parts) > 1 else ""
else:
    data['input_found'] = False

# Get All Feeds
# Returns: id \t name \t engine \t interval
sql_feeds = "SELECT id, name, engine, `interval` FROM feeds"
feeds_res = run_sql(sql_feeds)
data['feeds'] = []
if feeds_res:
    for line in feeds_res.split('\n'):
        if line.strip():
            parts = line.split('\t')
            data['feeds'].append({
                'id': parts[0],
                'name': parts[1],
                'engine': int(parts[2]),
                'interval': int(parts[3])
            })

# Get Process Map (Process ID -> Name)
# We can't easily query this from DB as it's in PHP code, 
# but we can assume standard Emoncms process IDs for verification.
# 1: Log to feed
# 22: Max daily
# 23: Min daily
# 24: Reset to Original
# 25: Reset to Zero

print(json.dumps(data))
EOF

# Run extraction
python3 /tmp/extract_data.py > /tmp/task_result.json

# 3. Add timestamp info
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Update JSON with timestamps using jq
jq --argjson start "$TASK_START" --argjson end "$TASK_END" \
   '. + {task_start: $start, task_end: $end}' \
   /tmp/task_result.json > /tmp/task_result_final.json

mv /tmp/task_result_final.json /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result data:"
cat /tmp/task_result.json

echo "=== Export complete ==="