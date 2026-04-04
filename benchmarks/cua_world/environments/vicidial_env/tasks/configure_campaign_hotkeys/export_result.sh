#!/bin/bash
set -e
echo "=== Exporting Configure Campaign Hotkeys Result ==="

source /workspace/scripts/task_utils.sh

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Extract Data from Database
# We need to check:
# - Campaign existence and settings (Active, HotKeys Active, Allow Closers)
# - HotKey entries

JSON_OUTPUT="/tmp/task_result.json"

# Python script to query DB and format JSON
# We run this inside the VM, using docker exec to reach the DB
python3 -c "
import subprocess
import json
import sys

def run_query(query):
    cmd = ['docker', 'exec', 'vicidial', 'mysql', '-ucron', '-p1234', '-D', 'asterisk', '-N', '-B', '-e', query]
    try:
        res = subprocess.check_output(cmd, stderr=subprocess.STDOUT)
        return res.decode('utf-8').strip()
    except subprocess.CalledProcessError:
        return ''

def run_query_dict(query, headers):
    raw = run_query(query)
    results = []
    if not raw:
        return results
    for line in raw.split('\n'):
        parts = line.split('\t')
        if len(parts) == len(headers):
            results.append(dict(zip(headers, parts)))
    return results

# 1. Get Campaign Info
camp_headers = ['campaign_id', 'campaign_name', 'active', 'allow_closers', 'hotkeys_active']
camp_query = \"SELECT campaign_id, campaign_name, active, allow_closers, hotkeys_active FROM vicidial_campaigns WHERE campaign_id='RAPID'\"
campaigns = run_query_dict(camp_query, camp_headers)

campaign_data = campaigns[0] if campaigns else None

# 2. Get HotKeys Info
hk_headers = ['hotkey', 'status', 'status_name_id']
hk_query = \"SELECT hotkey, status, status_name_id FROM vicidial_campaign_hotkeys WHERE campaign_id='RAPID' ORDER BY hotkey\"
hotkeys = run_query_dict(hk_query, hk_headers)

# 3. Construct Result
output = {
    'campaign_found': bool(campaign_data),
    'campaign_data': campaign_data,
    'hotkeys': hotkeys,
    'timestamp': run_query('SELECT NOW()')
}

with open('$JSON_OUTPUT', 'w') as f:
    json.dump(output, f, indent=2)
"

# 3. Add timestamp validation
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Append timing info to the JSON (using jq or python again, simpler to append via python above, 
# but let's just create a wrapper json or verify file mod time in python verifier)

# Set permissions so the host can read it
chmod 666 "$JSON_OUTPUT"

echo "Export complete. Result:"
cat "$JSON_OUTPUT"