#!/bin/bash
echo "=== Exporting Provider Enrichment Result ==="

source /workspace/scripts/task_utils.sh

# 1. Take Final Screenshot
take_screenshot /tmp/task_final.png

# 2. Collect Task Data
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
CSV_PATH="/home/ga/reference/providers.csv"
OUT_DIR="/home/ga/outbound_hl7"

# Read CSV Content (to verify against)
CSV_CONTENT=""
if [ -f "$CSV_PATH" ]; then
    CSV_CONTENT=$(cat "$CSV_PATH" | base64 -w 0)
fi

# Read Output Files
# We construct a JSON array of objects { "filename": "x", "content": "base64..." }
OUTPUT_FILES_JSON="[]"
COUNT=$(ls "$OUT_DIR"/*.hl7 2>/dev/null | wc -l)

if [ "$COUNT" -gt 0 ]; then
    # Use python to safely build the JSON array of file contents
    OUTPUT_FILES_JSON=$(python3 -c "
import os
import json
import base64
import glob

out_dir = '$OUT_DIR'
files = glob.glob(os.path.join(out_dir, '*.hl7'))
result = []

for fpath in files:
    try:
        with open(fpath, 'rb') as f:
            content = base64.b64encode(f.read()).decode('utf-8')
        result.append({
            'filename': os.path.basename(fpath),
            'content': content,
            'mtime': os.path.getmtime(fpath)
        })
    except Exception:
        pass

print(json.dumps(result))
")
fi

# 3. Inspect Channel Configuration via API
# We need to verify the agent used the Deploy Script
CHANNEL_CONFIG_JSON="{}"

# Get Channel List
CHANNELS_XML=$(curl -sk -u admin:admin -H "X-Requested-With: OpenAPI" https://localhost:8443/api/channels 2>/dev/null)

# Find our channel ID
CHANNEL_ID=$(echo "$CHANNELS_XML" | python3 -c "
import sys
import xml.etree.ElementTree as ET
try:
    root = ET.fromstring(sys.stdin.read())
    found_id = ''
    for chan in root.findall('channel'):
        name = chan.find('name').text
        if name == 'Provider_Enrichment':
            found_id = chan.find('id').text
            break
    print(found_id)
except:
    print('')
")

DEPLOY_SCRIPT=""
TRANSFORMER_SCRIPT=""
CHANNEL_STATUS="UNKNOWN"

if [ -n "$CHANNEL_ID" ]; then
    # Get Status
    STATUS_JSON=$(curl -sk -u admin:admin -H "X-Requested-With: OpenAPI" -H "Accept: application/json" "https://localhost:8443/api/channels/$CHANNEL_ID/status" 2>/dev/null)
    CHANNEL_STATUS=$(echo "$STATUS_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin).get('dashboardStatus',{}).get('state','UNKNOWN'))" 2>/dev/null)

    # Get Channel Detail for Scripts
    CHANNEL_DETAIL_XML=$(curl -sk -u admin:admin -H "X-Requested-With: OpenAPI" "https://localhost:8443/api/channels/$CHANNEL_ID" 2>/dev/null)
    
    # Extract scripts using python
    SCRIPTS_JSON=$(echo "$CHANNEL_DETAIL_XML" | python3 -c "
import sys
import json
import xml.etree.ElementTree as ET

deploy_script = ''
transformer_script = ''

try:
    root = ET.fromstring(sys.stdin.read())
    
    # Deploy script is a direct child of channel
    ds = root.find('deployScript')
    if ds is not None:
        deploy_script = ds.text or ''

    # Transformer script is deeper: sourceConnector -> transformer -> elements -> element -> properties -> script
    # We look broadly for any javascript in the transformer
    # A simple way is to dump the whole XML string for the verifier to parse if needed, 
    # or just extract strings that look like scripts.
    # Let's extract the deploy script specifically as that's the requirement.
    
except Exception as e:
    pass

print(json.dumps({'deploy_script': deploy_script}))
")
    
    DEPLOY_SCRIPT=$(echo "$SCRIPTS_JSON" | jq -r .deploy_script)
fi

# 4. Compile Final Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "csv_content_base64": "$CSV_CONTENT",
    "output_files": $OUTPUT_FILES_JSON,
    "channel_found": $(if [ -n "$CHANNEL_ID" ]; then echo "true"; else echo "false"; fi),
    "channel_id": "$CHANNEL_ID",
    "channel_status": "$CHANNEL_STATUS",
    "deploy_script_content_base64": "$(echo "$DEPLOY_SCRIPT" | base64 -w 0)",
    "timestamp": "$(date -Iseconds)"
}
EOF

# Save to destination
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
echo "=== Export Complete ==="