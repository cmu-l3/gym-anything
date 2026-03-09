#!/bin/bash
echo "=== Exporting update_hospital_settings result ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Query CouchDB for the configuration
echo "Querying configuration..."
# We search for documents containing the target strings or the configuration type
CONFIG_DATA=$(curl -s "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/_all_docs?include_docs=true" | \
    python3 -c "
import sys, json
data = json.load(sys.stdin)
found_docs = []
for row in data.get('rows', []):
    doc = row.get('doc', {})
    d = doc.get('data', doc)
    
    # Heuristic to find relevant config docs
    is_config = False
    if doc.get('_id') == 'configuration': is_config = True
    if d.get('type') == 'configuration': is_config = True
    if 'hospitalName' in d: is_config = True
    
    if is_config:
        found_docs.append({
            'id': doc.get('_id'),
            'rev': doc.get('_rev'),
            'hospitalName': d.get('hospitalName', ''),
            'hospitalEmail': d.get('hospitalEmail', ''),
            'full_doc': doc
        })

print(json.dumps(found_docs))
")

# 3. Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "config_documents": $CONFIG_DATA,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location
sudo mv "$TEMP_JSON" /tmp/task_result.json
sudo chmod 666 /tmp/task_result.json

echo "Export complete. Result saved to /tmp/task_result.json"