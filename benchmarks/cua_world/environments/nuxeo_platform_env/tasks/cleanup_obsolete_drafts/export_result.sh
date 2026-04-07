#!/bin/bash
echo "=== Exporting cleanup_obsolete_drafts results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Documents to check
DOCS=(
    "Project-Alpha-Draft-v1"
    "Project-Alpha-Draft-v2"
    "Project-Alpha-Final"
    "Project-Beta-Draft"
    "Regulatory-Reference"
)

# Initialize JSON array
JSON_DOCS=""
FIRST=1

for doc_name in "${DOCS[@]}"; do
    # Fetch document state and metadata via API
    # We use ?properties=* to get state and timestamps
    RESP=$(curl -s -u "$NUXEO_AUTH" "$NUXEO_URL/api/v1/path/default-domain/workspaces/Cleanup_Zone/$doc_name")
    
    # Extract info using python one-liner
    DOC_INFO=$(echo "$RESP" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    if 'status' in d and d['status'] == 404:
         print(json.dumps({'name': '$doc_name', 'exists': False, 'state': 'missing', 'modified': ''}))
    else:
         print(json.dumps({
            'name': '$doc_name',
            'exists': True,
            'state': d.get('state', 'unknown'),
            'modified': d.get('lastModified', ''),
            'is_trashed': d.get('isTrashed', False)
         }))
except:
    print(json.dumps({'name': '$doc_name', 'exists': False, 'state': 'error', 'modified': ''}))
")
    
    if [ "$FIRST" -eq 1 ]; then
        JSON_DOCS="$DOC_INFO"
        FIRST=0
    else
        JSON_DOCS="$JSON_DOCS, $DOC_INFO"
    fi
done

# Take final screenshot
ga_x "scrot /tmp/task_final.png" 2>/dev/null || true
SCREENSHOT_EXISTS="false"
if [ -f /tmp/task_final.png ]; then
    SCREENSHOT_EXISTS="true"
fi

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "screenshot_exists": $SCREENSHOT_EXISTS,
    "screenshot_path": "/tmp/task_final.png",
    "documents": [$JSON_DOCS]
}
EOF

# Move to final location with permission handling
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="