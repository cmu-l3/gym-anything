#!/bin/bash
set -e
echo "=== Exporting Screen Labels task result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Query the database for the HEALTH01 label
echo "Querying database for HEALTH01..."

# We fetch the row as JSON if possible, or just individual fields.
# Since mysql in the container might not support easy JSON export, we'll fetch fields line by line or csv.
# We will use python to construct a robust JSON.

cat > /tmp/query_label.py << 'PYEOF'
import subprocess
import json
import sys

def run_query(query):
    cmd = ["docker", "exec", "vicidial", "mysql", "-ucron", "-p1234", "-D", "asterisk", "-N", "-e", query]
    try:
        result = subprocess.check_output(cmd, stderr=subprocess.STDOUT)
        return result.decode('utf-8').strip()
    except subprocess.CalledProcessError:
        return ""

# Check if label exists
exists_query = "SELECT COUNT(*) FROM vicidial_screen_labels WHERE label_id='HEALTH01'"
count = run_query(exists_query)
exists = (count == "1")

data = {}
if exists:
    # Fetch specific columns
    cols = [
        "label_name", "label_title", "label_first_name", "label_last_name", 
        "label_address1", "label_address2", "label_address3", "label_city", 
        "label_state", "label_alt_phone", "label_email", "label_comments"
    ]
    
    # Construct query
    col_str = ", ".join([f"`{c}`" for c in cols])
    data_query = f"SELECT {col_str} FROM vicidial_screen_labels WHERE label_id='HEALTH01'"
    
    row_str = run_query(data_query)
    # Output is tab separated
    if row_str:
        values = row_str.split('\t')
        if len(values) == len(cols):
            for i, col in enumerate(cols):
                data[col] = values[i]

# Get initial count to verify it was created during task
try:
    with open('/tmp/initial_label_count.txt', 'r') as f:
        initial_count = int(f.read().strip())
except:
    initial_count = 0

result = {
    "exists": exists,
    "initial_count": initial_count,
    "data": data,
    "timestamp": run_query("SELECT NOW()"), # DB server time
    "screenshot_path": "/tmp/task_final.png"
}

print(json.dumps(result, indent=2))
PYEOF

# Run the python script and save output
python3 /tmp/query_label.py > /tmp/task_result.json

# Cleanup temp script
rm /tmp/query_label.py

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json

echo "=== Export complete ==="