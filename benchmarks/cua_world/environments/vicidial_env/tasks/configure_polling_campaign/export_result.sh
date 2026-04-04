#!/bin/bash
set -e

echo "=== Exporting task results ==="

source /workspace/scripts/task_utils.sh

# Record end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Database Helper
DB_CMD="docker exec vicidial mysql -ucron -p1234 -D asterisk -N -B -e"
DB_CMD_JSON="docker exec vicidial mysql -ucron -p1234 -D asterisk -e" # Includes headers for easier parsing if needed, but we'll specific queries

# 1. Inspect Campaign
echo "Querying Campaign..."
CAMPAIGN_DATA=$($DB_CMD "SELECT campaign_id, campaign_name, active, dial_method, auto_dial_level, campaign_script FROM vicidial_campaigns WHERE campaign_id='SENPOLL';" 2>/dev/null || true)

# 2. Inspect Statuses
echo "Querying Statuses..."
STATUS_DATA=$($DB_CMD "SELECT status, status_name, selectable, human_answered FROM vicidial_campaign_statuses WHERE campaign_id='SENPOLL';" 2>/dev/null || true)

# 3. Inspect Script
echo "Querying Script..."
# Use hex export for script text to avoid JSON escaping issues with newlines/quotes
SCRIPT_DATA=$($DB_CMD "SELECT script_id, script_name, HEX(script_text) FROM vicidial_scripts WHERE script_id='SENPOLLSC';" 2>/dev/null || true)

# 4. Inspect List
echo "Querying List..."
LIST_DATA=$($DB_CMD "SELECT list_id, campaign_id FROM vicidial_lists WHERE list_id='9001';" 2>/dev/null || true)

# Create JSON Result
# We will use python to construct valid JSON from the raw text outputs to avoid bash quoting hell
python3 -c "
import json
import sys

def parse_tab_data(raw_data, headers):
    results = []
    if not raw_data:
        return results
    for line in raw_data.strip().split('\n'):
        if not line: continue
        parts = line.split('\t')
        if len(parts) == len(headers):
            results.append(dict(zip(headers, parts)))
    return results

campaign_raw = '''$CAMPAIGN_DATA'''
status_raw = '''$STATUS_DATA'''
script_raw = '''$SCRIPT_DATA'''
list_raw = '''$LIST_DATA'''

campaign_headers = ['id', 'name', 'active', 'dial_method', 'auto_dial_level', 'script']
status_headers = ['status', 'name', 'selectable', 'human_answered']
script_headers = ['id', 'name', 'text_hex']
list_headers = ['list_id', 'campaign_id']

campaigns = parse_tab_data(campaign_raw, campaign_headers)
statuses = parse_tab_data(status_raw, status_headers)
scripts = parse_tab_data(script_raw, script_headers)
lists = parse_tab_data(list_raw, list_headers)

# Decode hex script text
for s in scripts:
    try:
        s['text'] = bytes.fromhex(s['text_hex']).decode('utf-8')
    except:
        s['text'] = ''
    del s['text_hex']

result = {
    'task_start': $TASK_START,
    'task_end': $TASK_END,
    'campaign': campaigns[0] if campaigns else None,
    'statuses': statuses,
    'script': scripts[0] if scripts else None,
    'list': lists[0] if lists else None
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
"

# Copy result to safe location
chmod 666 /tmp/task_result.json
echo "Result JSON generated at /tmp/task_result.json"
cat /tmp/task_result.json

echo "=== Export complete ==="