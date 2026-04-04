#!/bin/bash
echo "=== Exporting create_hospital_location result ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/create_location_final.png

# Query CouchDB for the new location
echo "Searching CouchDB for 'Cardiology Outpatient Center'..."

# We search for a document where 'name' or 'value' matches the target.
# HospitalRun lookups often look like { "type": "lookup_value", "value": "Name", "lookup_type": "Location" }
# Or sometimes just a location type document.
FOUND_DOC=$(curl -s "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/_all_docs?include_docs=true" 2>/dev/null | \
    python3 -c "
import sys, json
data = json.load(sys.stdin)
target = 'Cardiology Outpatient Center'
found = None

for row in data.get('rows', []):
    doc = row.get('doc', {})
    d = doc.get('data', doc)
    
    # Check name/value fields
    name = d.get('name', d.get('value', ''))
    
    if name == target:
        found = {
            'id': row['id'],
            'rev': doc.get('_rev', ''),
            'name': name,
            'type': d.get('type', doc.get('type', 'unknown')),
            'lookup_type': d.get('lookup_type', doc.get('lookup_type', '')),
            # Approximate creation check via checking if it exists
            # (Timestamp check handled by ensuring it wasn't there at start via setup script)
        }
        break

print(json.dumps(found) if found else '{}')
" 2>/dev/null || echo "{}")

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "doc_found": $(if [ "$(echo "$FOUND_DOC" | jq -r .name)" == "null" ]; then echo "false"; else echo "true"; fi),
    "document": $FOUND_DOC,
    "screenshot_path": "/tmp/create_location_final.png"
}
EOF

# Move to final location with permissions
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="