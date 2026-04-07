#!/bin/bash
echo "=== Exporting interactive_log_explorer result ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

echo "Querying Splunk REST API for the target dashboard..."
# Extract dashboard XML from the REST API
DASHBOARD_JSON_TEMP=$(mktemp /tmp/dashboard.XXXXXX.json)
curl -sk -u "admin:SplunkAdmin1!" \
    "https://localhost:8089/servicesNS/admin/search/data/ui/views/web_error_investigator?output_mode=json" \
    > "$DASHBOARD_JSON_TEMP" 2>/dev/null

# Process the JSON to cleanly extract just what the verifier needs
TEMP_RESULT_JSON=$(mktemp /tmp/result.XXXXXX.json)
python3 -c "
import sys, json, os

try:
    with open('$DASHBOARD_JSON_TEMP', 'r') as f:
        data = json.load(f)
    
    entries = data.get('entry', [])
    if entries:
        entry = entries[0]
        content = entry.get('content', {})
        xml_data = content.get('eai:data', '')
        updated = entry.get('updated', '')
        
        result = {
            'found': True,
            'xml': xml_data,
            'updated': updated,
            'task_start': $TASK_START,
            'task_end': $TASK_END
        }
    else:
        result = {
            'found': False, 
            'xml': '',
            'task_start': $TASK_START,
            'task_end': $TASK_END
        }
except Exception as e:
    result = {
        'found': False, 
        'error': str(e),
        'task_start': $TASK_START,
        'task_end': $TASK_END
    }

with open('$TEMP_RESULT_JSON', 'w') as f:
    json.dump(result, f, indent=2)
"

rm -f "$DASHBOARD_JSON_TEMP"

# Move to final location safely
safe_write_json "$TEMP_RESULT_JSON" /tmp/interactive_log_explorer_result.json

echo "Result saved to /tmp/interactive_log_explorer_result.json"
cat /tmp/interactive_log_explorer_result.json
echo "=== Export complete ==="