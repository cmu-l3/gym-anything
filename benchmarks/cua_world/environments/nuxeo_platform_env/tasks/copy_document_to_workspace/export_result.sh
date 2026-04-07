#!/bin/bash
echo "=== Exporting copy_document_to_workspace result ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
ORIGINAL_UID=$(cat /tmp/original_uid.txt 2>/dev/null || echo "")

# 1. Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Verify Original Document (Did they move it instead of copy?)
# We check if the document with the ORIGINAL UID still exists at the ORIGINAL PATH
ORIG_CHECK_JSON=$(nuxeo_api GET "/path/default-domain/workspaces/Projects/Annual-Report-2023")
ORIG_STILL_EXISTS=$(echo "$ORIG_CHECK_JSON" | python3 -c "import sys,json; print('true' if json.load(sys.stdin).get('uid') == '$ORIGINAL_UID' else 'false')" 2>/dev/null || echo "false")

# 3. Find the Copied Document in Templates
# We search for documents in Templates with the correct title
SEARCH_QUERY="SELECT * FROM Document WHERE ecm:path STARTSWITH '/default-domain/workspaces/Templates' AND dc:title = 'Annual Report 2023' AND ecm:isTrashed = 0"
SEARCH_QUERY_ENC=$(echo "$SEARCH_QUERY" | sed 's/ /%20/g')

COPY_SEARCH_JSON=$(curl -s -u "$NUXEO_AUTH" "$NUXEO_URL/api/v1/search/lang/NXQL/execute?query=$SEARCH_QUERY_ENC")

# Extract details of the found copy (if any)
# We get the first match
COPY_DETAILS=$(echo "$COPY_SEARCH_JSON" | python3 -c "
import sys, json
data = json.load(sys.stdin)
entries = data.get('entries', [])
if entries:
    doc = entries[0]
    props = doc.get('properties', {})
    print(json.dumps({
        'found': True,
        'uid': doc.get('uid'),
        'path': doc.get('path'),
        'title': props.get('dc:title'),
        'created': props.get('dc:created'),
        'has_content': props.get('file:content') is not None
    }))
else:
    print(json.dumps({'found': False}))
")

# 4. Generate Result JSON
# Use a temp file to avoid permission issues during creation
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)

cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $TASK_START,
    "original_uid_start": "$ORIGINAL_UID",
    "original_still_exists_at_source": $ORIG_STILL_EXISTS,
    "copy_document": $COPY_DETAILS,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="