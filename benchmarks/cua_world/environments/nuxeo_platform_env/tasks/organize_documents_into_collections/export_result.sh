#!/bin/bash
echo "=== Exporting task results ==="

source /workspace/scripts/task_utils.sh

# 1. Capture Final Screenshot
ga_x "scrot /tmp/task_final.png" 2>/dev/null || true

# 2. Query Nuxeo API to verify state
# We need to find the UIDs of the created collections and check the documents.

echo "Querying Nuxeo state..."

# Helper to get Collection UID by title
get_collection_uid() {
    local title="$1"
    local query="SELECT * FROM Collection WHERE dc:title = '$title' AND ecm:isTrashed = 0"
    curl -s -u "$NUXEO_AUTH" -G --data-urlencode "query=$query" "$NUXEO_URL/api/v1/search/lang/NXQL/execute" | \
        python3 -c "import sys, json; data=json.load(sys.stdin); entries=data.get('entries',[]); print(entries[0]['uid'] if entries else '')"
}

# Helper to get Document Collection IDs
get_doc_collection_ids() {
    local path="$1"
    # We use the 'collectionMember' enricher to see collections, or check the property directly if available.
    # The 'collectionMember:collectionIds' property is the standard way.
    curl -s -u "$NUXEO_AUTH" -H "X-NXproperties: *" "$NUXEO_URL/api/v1/path$path" | \
        python3 -c "import sys, json; data=json.load(sys.stdin); print(json.dumps(data.get('properties', {}).get('collectionMember:collectionIds', [])))"
}

# Get IDs for the target collections
FINANCE_UID=$(get_collection_uid "Finance Resources")
STRATEGY_UID=$(get_collection_uid "Strategy Resources")

# Get collection memberships for the documents
DOC1_COLS=$(get_doc_collection_ids "/default-domain/workspaces/Projects/Annual-Report-2023")
DOC2_COLS=$(get_doc_collection_ids "/default-domain/workspaces/Projects/Project-Proposal")
DOC3_COLS=$(get_doc_collection_ids "/default-domain/workspaces/Projects/Q3-Status-Report")

# Get creation timestamps for collections (Anti-gaming)
FINANCE_CREATED_AT=""
STRATEGY_CREATED_AT=""

if [ -n "$FINANCE_UID" ]; then
    FINANCE_CREATED_AT=$(nuxeo_api GET "/id/$FINANCE_UID" | python3 -c "import sys, json; print(json.load(sys.stdin).get('properties',{}).get('dc:created',''))")
fi
if [ -n "$STRATEGY_UID" ]; then
    STRATEGY_CREATED_AT=$(nuxeo_api GET "/id/$STRATEGY_UID" | python3 -c "import sys, json; print(json.load(sys.stdin).get('properties',{}).get('dc:created',''))")
fi

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 3. Construct Result JSON
# We use a python script to safely build the JSON to avoid quoting issues
python3 -c "
import json
import os

result = {
    'task_start': $TASK_START,
    'task_end': $TASK_END,
    'finance_collection_uid': '$FINANCE_UID',
    'strategy_collection_uid': '$STRATEGY_UID',
    'finance_created_at': '$FINANCE_CREATED_AT',
    'strategy_created_at': '$STRATEGY_CREATED_AT',
    'doc_annual_report_collections': $DOC1_COLS,
    'doc_proposal_collections': $DOC2_COLS,
    'doc_q3_report_collections': $DOC3_COLS,
    'screenshot_path': '/tmp/task_final.png'
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
"

# Set permissions so verifier can copy it
chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="