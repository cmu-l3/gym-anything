#!/bin/bash
echo "=== Exporting Kiosk Dashboard Result ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record timestamps
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# -----------------------------------------------------------------------
# 1. Capture Final Screenshot
# -----------------------------------------------------------------------
take_screenshot /tmp/task_final.png

# -----------------------------------------------------------------------
# 2. Extract Data from Database
# -----------------------------------------------------------------------
# We need:
# A. The IDs of the target dashboards (Ground Truth)
# B. The content of the "Facility Kiosk" dashboard (Agent Output)

echo "Querying database for dashboard info..."

# Helper for JSON-safe SQL output
run_sql_json() {
    local query="$1"
    # Run query, output as tab-separated, then use jq to format if possible, 
    # or just raw text processing. Here we construct a JSON manually or use python.
    docker exec emoncms-db mysql -u emoncms -pemoncms emoncms -N -e "$query" 2>/dev/null
}

# Python script to extract DB data and format as JSON
# This is more robust for handling the nested JSON in the 'content' column
cat > /tmp/extract_db_data.py << 'PYEOF'
import json
import subprocess
import sys

def run_query(sql):
    cmd = ["docker", "exec", "emoncms-db", "mysql", "-u", "emoncms", "-pemoncms", "emoncms", "-N", "-B", "-e", sql]
    res = subprocess.run(cmd, capture_output=True, text=True)
    return res.stdout.strip()

data = {
    "targets": {},
    "kiosk": None
}

# Get Targets
try:
    # Get IDs for specific names
    names = ["Solar Array A", "HVAC Main", "Lighting Zones"]
    names_str = "'" + "','".join(names) + "'"
    raw = run_query(f"SELECT name, id FROM dashboard WHERE name IN ({names_str})")
    for line in raw.split('\n'):
        if line:
            parts = line.split('\t')
            if len(parts) >= 2:
                data["targets"][parts[0]] = int(parts[1])
except Exception as e:
    data["error_targets"] = str(e)

# Get Kiosk Data
try:
    # Select content of Facility Kiosk
    # Note: 'content' column stores the widgets JSON string
    raw_kiosk = run_query("SELECT id, content FROM dashboard WHERE name='Facility Kiosk' ORDER BY id DESC LIMIT 1")
    if raw_kiosk:
        parts = raw_kiosk.split('\t')
        kiosk_id = int(parts[0])
        # The content might contain tabs or newlines, so we need to be careful.
        # Ideally, we fetch just the ID first, then fetch content carefully?
        # Actually, MySQL -B output escapes tabs/newlines.
        # Let's try to just get the raw string.
        
        # Better approach: Python inside container or carefully reading stdout
        # Simple hack: Use the raw string, the verifier can parse the internal JSON
        content_str = parts[1] if len(parts) > 1 else "[]"
        data["kiosk"] = {
            "id": kiosk_id,
            "content_raw": content_str
        }
except Exception as e:
    data["error_kiosk"] = str(e)

print(json.dumps(data, indent=2))
PYEOF

# Run the extraction
python3 /tmp/extract_db_data.py > /tmp/db_data.json

# -----------------------------------------------------------------------
# 3. Create Final Result JSON
# -----------------------------------------------------------------------
# Merge DB data with task metadata
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
python3 -c "
import json
import os

try:
    with open('/tmp/db_data.json', 'r') as f:
        db_data = json.load(f)
except:
    db_data = {}

result = {
    'task_start': $TASK_START,
    'task_end': $TASK_END,
    'screenshot_path': '/tmp/task_final.png',
    'db_data': db_data
}

with open('$TEMP_JSON', 'w') as f:
    json.dump(result, f, indent=2)
"

# Move to final location with permissions
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="