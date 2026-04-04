#!/bin/bash
echo "=== Exporting version_control_document results ==="

source /workspace/scripts/task_utils.sh

# 1. Basic info
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
CASE_ID=$(cat /tmp/case_id.txt 2>/dev/null || echo "")

# 2. Screenshot
take_screenshot /tmp/task_final.png

# 3. Query ArkCase API for documents in the case
# We need to find the document "Investigation_Plan.txt"
echo "Querying API for documents..."
DOCS_JSON=$(arkcase_api GET "plugin/complaint/${CASE_ID}/documents")

# Save raw response for debug
echo "$DOCS_JSON" > /tmp/api_docs_debug.json

# 4. Extract details for verification
# We look for a document with title "Investigation_Plan.txt"
# We extract: objectId, versionLabel, title
DOC_INFO=$(echo "$DOCS_JSON" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    # Data is usually a list of document objects
    target_doc = None
    count = 0
    for doc in data:
        # Check title or name
        if 'Investigation_Plan.txt' in doc.get('title', '') or 'Investigation_Plan.txt' in doc.get('name', ''):
            target_doc = doc
        if 'Investigation_Plan' in doc.get('title', ''):
            count += 1
            
    if target_doc:
        print(json.dumps({
            'found': True,
            'objectId': target_doc.get('objectId', target_doc.get('id', '')),
            'versionLabel': target_doc.get('versionLabel', target_doc.get('version', '0.0')),
            'title': target_doc.get('title', ''),
            'count': count
        }))
    else:
        print(json.dumps({'found': False, 'count': count}))
except Exception as e:
    print(json.dumps({'found': False, 'error': str(e)}))
" 2>/dev/null)

# 5. Verify Content (if doc found)
# We need to download the file content.
# Endpoint: /api/v1/dms/object/{objectId}/download or similar
CONTENT_MATCH="false"
OBJECT_ID=$(echo "$DOC_INFO" | jq -r '.objectId')

if [ "$OBJECT_ID" != "null" ] && [ -n "$OBJECT_ID" ]; then
    echo "Downloading content for Object ID: $OBJECT_ID"
    # Download using the generic API helper, assuming standard download endpoint
    # Note: arkcase_api helper adds base URL and auth. 
    # We might need -L for redirects and output to file.
    
    # Construct download URL manually to use curl -L -o
    DOWNLOAD_URL="${ARKCASE_URL}/api/v1/dms/object/${OBJECT_ID}/download"
    curl -skL -u "${ARKCASE_ADMIN}:${ARKCASE_PASS}" "$DOWNLOAD_URL" -o /tmp/downloaded_doc.txt
    
    if grep -q "APPROVED FINAL CONTENT" /tmp/downloaded_doc.txt; then
        CONTENT_MATCH="true"
    fi
    
    # Anti-gaming: Check if the downloaded file has the Draft content (FAIL)
    if grep -q "DRAFT CONTENT" /tmp/downloaded_doc.txt; then
        CONTENT_IS_DRAFT="true"
    else
        CONTENT_IS_DRAFT="false"
    fi
else
    CONTENT_MATCH="false"
    CONTENT_IS_DRAFT="false"
fi

# 6. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "case_id": "$CASE_ID",
    "doc_info": $DOC_INFO,
    "content_match": $CONTENT_MATCH,
    "content_is_draft": $CONTENT_IS_DRAFT,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="