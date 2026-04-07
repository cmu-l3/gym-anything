#!/bin/bash
# Setup script for start_document_workflow task
# Prepares the Nuxeo environment, ensures the document and user exist,
# clears old workflows, and positions the agent on the document page.

set -e
echo "=== Setting up start_document_workflow task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Wait for Nuxeo to be ready
wait_for_nuxeo 120

echo "Ensuring user 'jsmith' exists..."
# Check if user exists, create if not
if ! nuxeo_api GET "/user/jsmith" | grep -q '"username":"jsmith"'; then
    echo "Creating user jsmith..."
    PAYLOAD='{"entity-type":"user","id":"jsmith","properties":{"username":"jsmith","firstName":"John","lastName":"Smith","email":"jsmith@example.com","password":"password123","groups":["members"]}}'
    nuxeo_api POST "/user" "$PAYLOAD" > /dev/null
fi

echo "Ensuring 'Project Proposal' document exists..."
# Ensure the Projects workspace exists
create_doc_if_missing "/default-domain/workspaces" "Workspace" "Projects" "Projects" "Workspace for projects" > /dev/null

# Ensure the Project Proposal document exists
# We use the helper from task_utils or upload it if missing
if ! doc_exists "/default-domain/workspaces/Projects/Project-Proposal"; then
    echo "Uploading Project Proposal..."
    # If the file isn't in the data dir, use a dummy or copy from workspace
    PDF_SOURCE="/workspace/data/project_proposal.pdf"
    if [ ! -f "$PDF_SOURCE" ]; then
        PDF_SOURCE="/home/ga/nuxeo/data/Project_Proposal.pdf"
    fi
    
    if [ -f "$PDF_SOURCE" ]; then
        # Use the upload logic (simplified here as raw curl for robustness)
        BATCH_ID=$(curl -s -u "$NUXEO_AUTH" -X POST "$NUXEO_URL/api/v1/upload/" | python3 -c "import sys,json; print(json.load(sys.stdin).get('batchId',''))")
        curl -s -u "$NUXEO_AUTH" -X POST "$NUXEO_URL/api/v1/upload/$BATCH_ID/0" \
            -H "Content-Type: application/octet-stream" \
            -H "X-File-Name: Project_Proposal.pdf" \
            --data-binary @"$PDF_SOURCE" > /dev/null
            
        DOC_PAYLOAD='{"entity-type":"document","type":"File","name":"Project-Proposal","properties":{"dc:title":"Project Proposal","file:content":{"upload-batch":"'$BATCH_ID'","upload-fileId":"0"}}}'
        nuxeo_api POST "/path/default-domain/workspaces/Projects" "$DOC_PAYLOAD" > /dev/null
    else
        # Fallback to creating a Note if PDF missing (shouldn't happen in valid env)
        create_doc_if_missing "/default-domain/workspaces/Projects" "Note" "Project-Proposal" "Project Proposal" "Proposal content..." > /dev/null
    fi
fi

# Get Document UID
DOC_UID=$(nuxeo_api GET "/path/default-domain/workspaces/Projects/Project-Proposal" | python3 -c "import sys,json; print(json.load(sys.stdin).get('uid',''))")
echo "Document UID: $DOC_UID"
echo "$DOC_UID" > /tmp/target_doc_uid.txt

echo "Clearing existing workflows on the document..."
# Get all running workflows on this doc and cancel them
WORKFLOWS=$(nuxeo_api GET "/id/$DOC_UID/@workflow")
echo "$WORKFLOWS" | python3 -c "
import sys, json
data = json.load(sys.stdin)
for entry in data.get('entries', []):
    print(entry.get('id'))
" | while read -r wf_id; do
    if [ -n "$wf_id" ]; then
        echo "Cancelling workflow $wf_id..."
        nuxeo_api DELETE "/workflow/$wf_id" > /dev/null || true
    fi
done

# Record initial workflow count (Anti-gaming: ensures we start at 0)
INITIAL_COUNT=$(nuxeo_api GET "/id/$DOC_UID/@workflow" | python3 -c "import sys,json; print(len(json.load(sys.stdin).get('entries',[])))")
echo "$INITIAL_COUNT" > /tmp/initial_workflow_count.txt
echo "Initial workflow count: $INITIAL_COUNT"

# Launch Browser
echo "Launching Firefox..."
# Open directly to the document page
DOC_URL="$NUXEO_UI/#!/browse/default-domain/workspaces/Projects/Project-Proposal"
open_nuxeo_url "$NUXEO_URL/login.jsp" 8

# Check if we need to login
sleep 5
PAGE_TITLE=$(ga_x "xdotool getactivewindow getwindowname" 2>/dev/null || echo "")
if ! echo "$PAGE_TITLE" | grep -q " - Nuxeo Platform"; then
    nuxeo_login
fi

# Navigate explicitly to the document to be sure
navigate_to "$DOC_URL"

# Final check of state
ga_x "wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz" 2>/dev/null || true
ga_x "scrot /tmp/task_initial.png" 2>/dev/null || true

echo "=== Setup complete ==="