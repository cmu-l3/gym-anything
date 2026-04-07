#!/bin/bash
set -e
echo "=== Setting up copy_document_to_workspace task ==="

source /workspace/scripts/task_utils.sh

# 1. Record task start time
date +%s > /tmp/task_start_time.txt

# 2. Wait for Nuxeo to be ready
wait_for_nuxeo 180

# 3. Ensure Original Document exists in Projects
# We use the REST API to check/create to ensure a known starting state
echo "Ensuring original document exists..."
if ! doc_exists "/default-domain/workspaces/Projects/Annual-Report-2023"; then
    # Create if missing (using the utility function which handles file upload if needed)
    # For setup speed, we might just create the metadata if the blob isn't strictly required for *existence*,
    # but the task implies content. We'll assume the environment setup (setup_nuxeo.sh) did the heavy lifting,
    # but we verify here.
    
    # Fallback creation if setup_nuxeo.sh failed or was modified
    DATA_FILE="/home/ga/nuxeo/data/Annual_Report_2023.pdf"
    if [ ! -f "$DATA_FILE" ]; then DATA_FILE="/workspace/data/annual_report_2023.pdf"; fi
    
    if [ -f "$DATA_FILE" ]; then
        # Quick upload logic if needed, usually pre-handled by env setup
        BATCH_ID=$(curl -s -u "$NUXEO_AUTH" -X POST "$NUXEO_URL/api/v1/upload/" | python3 -c "import sys,json; print(json.load(sys.stdin).get('batchId',''))")
        curl -s -u "$NUXEO_AUTH" -X POST "$NUXEO_URL/api/v1/upload/$BATCH_ID/0" --data-binary @"$DATA_FILE" > /dev/null
        
        PAYLOAD='{"entity-type":"document","type":"File","name":"Annual-Report-2023","properties":{"dc:title":"Annual Report 2023","file:content":{"upload-batch":"'$BATCH_ID'","upload-fileId":"0"}}}'
        nuxeo_api POST "/path/default-domain/workspaces/Projects/" "$PAYLOAD" > /dev/null
    fi
fi

# 4. Record Original UID (CRITICAL for verification)
ORIG_JSON=$(nuxeo_api GET "/path/default-domain/workspaces/Projects/Annual-Report-2023")
ORIG_UID=$(echo "$ORIG_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin).get('uid',''))")
echo "$ORIG_UID" > /tmp/original_uid.txt
echo "Original Document UID: $ORIG_UID"

# 5. Ensure Target Workspace (Templates) exists
if ! doc_exists "/default-domain/workspaces/Templates"; then
    create_doc_if_missing "/default-domain/workspaces" "Workspace" "Templates" "Templates" "Templates Workspace"
fi

# 6. CLEANUP: Ensure the document does NOT exist in Templates (Pre-condition)
# We search for any document with this title in Templates and delete it
echo "Cleaning up target workspace..."
SEARCH_QUERY="SELECT * FROM Document WHERE ecm:path STARTSWITH '/default-domain/workspaces/Templates' AND dc:title = 'Annual Report 2023'"
# Encode spaces
SEARCH_QUERY_ENC=$(echo "$SEARCH_QUERY" | sed 's/ /%20/g')

TO_DELETE=$(curl -s -u "$NUXEO_AUTH" "$NUXEO_URL/api/v1/search/lang/NXQL/execute?query=$SEARCH_QUERY_ENC" | \
    python3 -c "import sys,json; print(' '.join([d['uid'] for d in json.load(sys.stdin).get('entries',[])]))")

for uid in $TO_DELETE; do
    echo "Deleting stale copy: $uid"
    nuxeo_api DELETE "/id/$uid" > /dev/null
done

# 7. Prepare Browser
# Open Firefox, login, and navigate to the Projects workspace (starting point)
open_nuxeo_url "$NUXEO_UI/#!/browse/default-domain/workspaces/Projects" 8
nuxeo_login

# 8. Initial Screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="