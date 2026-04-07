#!/bin/bash
echo "=== Exporting create_soc_macros result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Fetch all current macros
echo "Fetching current macros..."
curl -sk -u "${SPLUNK_USER}:${SPLUNK_PASS}" \
    "${SPLUNK_API}/servicesNS/-/-/admin/macros?output_mode=json&count=0" \
    > /tmp/current_macros_raw.json 2>/dev/null

# Process initial and current macros into a clean JSON for the verifier
python3 - << 'PYEOF'
import sys, json, os

try:
    with open('/tmp/initial_macros.json', 'r') as f:
        initial_macros = json.load(f)
except:
    initial_macros = []

try:
    with open('/tmp/current_macros_raw.json', 'r') as f:
        current_raw = json.load(f)
    
    current_macros = {}
    for entry in current_raw.get('entry', []):
        name = entry.get('name', '')
        content = entry.get('content', {})
        current_macros[name] = {
            'definition': content.get('definition', ''),
            'args': content.get('args', ''),
            'updated': entry.get('updated', '')
        }
except Exception as e:
    current_macros = {}

output = {
    "initial_macros": initial_macros,
    "current_macros": current_macros,
    "total_current": len(current_macros),
    "total_initial": len(initial_macros)
}

with open('/tmp/macro_results_temp.json', 'w') as f:
    json.dump(output, f, indent=2)
PYEOF

# Safely copy to final location
safe_write_json /tmp/macro_results_temp.json /tmp/macro_results.json

echo "Result saved to /tmp/macro_results.json"
echo "=== Export complete ==="