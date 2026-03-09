#!/bin/bash
echo "=== Exporting Results ==="

source /workspace/scripts/task_utils.sh

# 1. Capture Final State
take_screenshot /tmp/task_final.png
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
CASE_ID=$(cat /tmp/task_case_id.txt 2>/dev/null || echo "")

# 2. Query ArkCase API for Documents in the Case
# We need to find the files uploaded to this case.
# Strategy: List objects associated with the complaint.

echo "Querying API for case documents..."
# This endpoint typically lists children/contents of the case container
# Adjust endpoint based on specific ArkCase version, but "plugin/complaint/{id}/documents" or similar is standard pattern
# If not, we search for files with specific names via Solr/Search API
DOCS_RESPONSE=$(arkcase_api GET "plugin/complaint/${CASE_ID}/references" 2>/dev/null || echo "[]")

# Save raw response for debugging
echo "$DOCS_RESPONSE" > /tmp/api_response_raw.json

# Extract relevant document info
python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    # data might be a list of references or a complex object
    # normalization logic:
    docs = []
    if isinstance(data, list):
        docs = data
    elif isinstance(data, dict) and 'references' in data:
        docs = data['references']
    
    # Filter for our expected files
    found_files = []
    for d in docs:
        name = d.get('title', d.get('name', ''))
        # If the API returns full objects, we might check timestamps
        created = d.get('createdDate', d.get('created', 0))
        found_files.append({'name': name, 'created': created, 'id': d.get('objectGuid', d.get('id', ''))})
    
    print(json.dumps(found_files))
except Exception as e:
    print(json.dumps([]))
" < /tmp/api_response_raw.json > /tmp/case_documents.json

# 3. Check local file (ensure agent didn't delete the source)
LOCAL_SOURCE_EXISTS="false"
if [ -f "/home/ga/Documents/Access_Logs_2025.xlsx" ]; then
    LOCAL_SOURCE_EXISTS="true"
fi

# 4. Construct Result JSON
cat > /tmp/task_result.json << EOF
{
    "task_start_timestamp": $TASK_START,
    "case_id": "$CASE_ID",
    "local_source_preserved": $LOCAL_SOURCE_EXISTS,
    "screenshot_path": "/tmp/task_final.png",
    "api_documents_path": "/tmp/case_documents.json"
}
EOF

# Permission fix
chmod 666 /tmp/task_result.json 2>/dev/null || true
echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json