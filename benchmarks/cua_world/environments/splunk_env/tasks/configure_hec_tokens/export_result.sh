#!/bin/bash
echo "=== Exporting configure_hec_tokens result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Wait a few seconds to allow any recently submitted HEC events to finish indexing
echo "Waiting for indexing to flush..."
sleep 10

# Gather HEC Global state
curl -sk -u "admin:SplunkAdmin1!" "https://localhost:8089/services/data/inputs/http/http?output_mode=json" > /tmp/hec_global.json 2>/dev/null

# Gather Index state
curl -sk -u "admin:SplunkAdmin1!" "https://localhost:8089/services/data/indexes/cloud_apps?output_mode=json" > /tmp/index_info.json 2>/dev/null

# Gather Tokens state
curl -sk -u "admin:SplunkAdmin1!" "https://localhost:8089/servicesNS/-/-/data/inputs/http?output_mode=json&count=0" > /tmp/tokens_info.json 2>/dev/null

# Gather Event Count for the new index
splunk_count_events "cloud_apps" > /tmp/event_count.txt

# Use Python to safely parse the REST API responses and compile a final JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
python3 - << 'PYEOF' > "$TEMP_JSON"
import json
import os

def read_json(path):
    try:
        if os.path.exists(path):
            with open(path, 'r') as f:
                return json.load(f)
    except Exception as e:
        pass
    return {}

hec_global = read_json('/tmp/hec_global.json')
index_info = read_json('/tmp/index_info.json')
tokens_info = read_json('/tmp/tokens_info.json')

# 1. Check if HEC is globally enabled
hec_enabled = False
if hec_global.get('entry'):
    content = hec_global['entry'][0].get('content', {})
    disabled_val = content.get('disabled', True)
    if isinstance(disabled_val, bool):
        hec_enabled = not disabled_val
    else:
        hec_enabled = str(disabled_val) in ['0', 'false', 'False']

# 2. Check if cloud_apps index exists
index_exists = len(index_info.get('entry', [])) > 0

# 3. Find our specific tokens
frontend_token = None
backend_token = None

for t in tokens_info.get('entry', []):
    name = t.get('name', '')
    # The name may be returned as 'http://webapp_frontend' or just 'webapp_frontend'
    if name.endswith('webapp_frontend'):
        frontend_token = t.get('content', {})
        frontend_token['raw_name'] = name
    elif name.endswith('webapp_backend'):
        backend_token = t.get('content', {})
        backend_token['raw_name'] = name

# 4. Get event count
event_count = 0
try:
    if os.path.exists('/tmp/event_count.txt'):
        with open('/tmp/event_count.txt', 'r') as f:
            val = f.read().strip()
            if val.isdigit():
                event_count = int(val)
except:
    pass

# Assemble the result
result = {
    "hec_globally_enabled": hec_enabled,
    "cloud_apps_index_exists": index_exists,
    "frontend_token": frontend_token,
    "backend_token": backend_token,
    "event_count": event_count,
    "export_timestamp": os.popen('date -Iseconds').read().strip()
}

print(json.dumps(result))
PYEOF

safe_write_json "$TEMP_JSON" /tmp/task_result.json

echo "Result saved to /tmp/task_result.json:"
cat /tmp/task_result.json
echo "=== Export complete ==="