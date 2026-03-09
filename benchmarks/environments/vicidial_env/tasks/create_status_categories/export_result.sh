#!/bin/bash
set -e

echo "=== Exporting Create Status Categories Result ==="

source /workspace/scripts/task_utils.sh

# Record end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Capture final screenshot
take_screenshot /tmp/task_final.png

# Query Database for Categories
# We format as JSON manually or CSV to parse later. Python is safest.
echo "Querying Vicidial Database..."

# Helper to run query and export to JSON-compatible format
# We select specific columns
CAT_QUERY="SELECT vsc_id, vsc_name, sale_category, dead_lead_category FROM vicidial_status_categories WHERE vsc_id IN ('SALES','DNCLST','FOLLOWUP','NOANSWER');"
STATUS_QUERY="SELECT status, status_name, category, human_answered, scheduled_callback FROM vicidial_statuses WHERE status IN ('SOLD','UPGRD','DNCREQ','CBPEND','NOPICK');"

# Execute queries
# Using -N (skip headers) and tab separation, we'll parse in Python script below to generate the JSON
docker exec vicidial mysql -ucron -p1234 -D asterisk -N -e "$CAT_QUERY" > /tmp/cats_found.txt 2>/dev/null || true
docker exec vicidial mysql -ucron -p1234 -D asterisk -N -e "$STATUS_QUERY" > /tmp/statuses_found.txt 2>/dev/null || true

# Create JSON result
python3 -c "
import json
import time

result = {
    'task_start': $TASK_START,
    'task_end': $TASK_END,
    'categories': [],
    'statuses': []
}

try:
    with open('/tmp/cats_found.txt', 'r') as f:
        for line in f:
            parts = line.strip().split('\t')
            if len(parts) >= 4:
                result['categories'].append({
                    'id': parts[0],
                    'name': parts[1],
                    'sale': parts[2],
                    'dead': parts[3]
                })

    with open('/tmp/statuses_found.txt', 'r') as f:
        for line in f:
            parts = line.strip().split('\t')
            if len(parts) >= 5:
                result['statuses'].append({
                    'id': parts[0],
                    'name': parts[1],
                    'category': parts[2],
                    'human': parts[3],
                    'callback': parts[4]
                })
except Exception as e:
    result['error'] = str(e)

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
"

# Permission fix
chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="