#!/bin/bash
# setup_task.sh for complete_review_workflow_task
# Starts a workflow and fast-forwards it to the validation step for the agent.

set -e
echo "=== Setting up Complete Review Workflow Task ==="

source /workspace/scripts/task_utils.sh

# 1. Wait for Nuxeo to be ready
wait_for_nuxeo 180

# 2. Ensure the document exists
DOC_PATH="/default-domain/workspaces/Projects/Annual-Report-2023"
if ! doc_exists "$DOC_PATH"; then
    echo "Creating Annual Report 2023..."
    # Ensure Projects workspace exists
    if ! doc_exists "/default-domain/workspaces/Projects"; then
        create_doc "/default-domain/workspaces" "Workspace" "Projects" "Projects" "Project Workspace" > /dev/null
    fi
    # Create the file (using the util function or raw API if needed)
    # We'll use a simple file creation
    DATA_FILE="/home/ga/nuxeo/data/Annual_Report_2023.pdf"
    if [ ! -f "$DATA_FILE" ]; then DATA_FILE="/workspace/data/Annual_Report_2023.pdf"; fi
    
    # Simple placeholder if real file missing
    if [ ! -f "$DATA_FILE" ]; then
        echo "Warning: Real PDF not found, creating dummy."
        echo "Dummy PDF content" > /tmp/dummy.pdf
        DATA_FILE="/tmp/dummy.pdf"
    fi
    
    # Upload and create (simplified for setup reliability)
    # We use the task_utils helper if available, or raw curl
    BATCH_RESP=$(curl -s -u "$NUXEO_AUTH" -X POST "$NUXEO_URL/api/v1/upload/")
    BATCH_ID=$(echo "$BATCH_RESP" | python3 -c "import sys,json; print(json.load(sys.stdin).get('batchId',''))" 2>/dev/null)
    
    curl -s -u "$NUXEO_AUTH" -X POST "$NUXEO_URL/api/v1/upload/$BATCH_ID/0" \
        -H "Content-Type: application/octet-stream" \
        --data-binary @"$DATA_FILE" > /dev/null
        
    PAYLOAD="{\"entity-type\":\"document\",\"type\":\"File\",\"name\":\"Annual-Report-2023\",\"properties\":{\"dc:title\":\"Annual Report 2023\",\"file:content\":{\"upload-batch\":\"$BATCH_ID\",\"upload-fileId\":\"0\"}}}"
    nuxeo_api POST "/path/default-domain/workspaces/Projects/" "$PAYLOAD" > /dev/null
fi

# Get Doc UID
DOC_INFO=$(nuxeo_api GET "/path$DOC_PATH")
DOC_UID=$(echo "$DOC_INFO" | python3 -c "import sys,json; print(json.load(sys.stdin).get('uid',''))" 2>/dev/null)
echo "$DOC_UID" > /tmp/task_doc_uid.txt

# 3. Clean up any existing workflows on this doc
echo "Cleaning existing workflows..."
WFS_JSON=$(curl -s -u "$NUXEO_AUTH" "$NUXEO_URL/api/v1/id/$DOC_UID/@workflow")
echo "$WFS_JSON" | python3 -c "import sys,json; print('\n'.join([e['id'] for e in json.load(sys.stdin).get('entries',[])]))" | while read wfid; do
    if [ -n "$wfid" ]; then
        curl -s -u "$NUXEO_AUTH" -X DELETE "$NUXEO_URL/api/v1/workflow/$wfid" > /dev/null
    fi
done

# 4. Start Serial Document Review Workflow
echo "Starting workflow..."
WF_RESP=$(curl -s -u "$NUXEO_AUTH" -H "Content-Type: application/json" -X POST "$NUXEO_URL/api/v1/id/$DOC_UID/@workflow" -d '{"entity-type":"workflow","workflowModelName":"SerialDocumentReview"}')
WF_ID=$(echo "$WF_RESP" | python3 -c "import sys,json; print(json.load(sys.stdin).get('id',''))")
echo "$WF_ID" > /tmp/task_workflow_id.txt
echo "Workflow started: $WF_ID"

sleep 2

# 5. Find the 'Choose Participants' task
TASKS_JSON=$(curl -s -u "$NUXEO_AUTH" "$NUXEO_URL/api/v1/task?workflowInstanceId=$WF_ID&userId=Administrator")
TASK_ID=$(echo "$TASKS_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin).get('entries',[{}])[0].get('id',''))")

if [ -z "$TASK_ID" ]; then
    echo "ERROR: Could not find initial workflow task."
    exit 1
fi

# 6. Complete 'Choose Participants' -> Assign to Administrator
echo "Completing setup task ($TASK_ID)..."
curl -s -u "$NUXEO_AUTH" -H "Content-Type: application/json" -X PUT "$NUXEO_URL/api/v1/task/$TASK_ID/start_review" \
    -d '{"entity-type":"task","id":"'"$TASK_ID"'","variables":{"participants":["user:Administrator"],"validationOrReview":"simpleReview"}}' > /dev/null

sleep 2

# Verify the Validate task is now pending
PENDING_JSON=$(curl -s -u "$NUXEO_AUTH" "$NUXEO_URL/api/v1/task?workflowInstanceId=$WF_ID&userId=Administrator")
PENDING_COUNT=$(echo "$PENDING_JSON" | python3 -c "import sys,json; print(len(json.load(sys.stdin).get('entries',[])))")
echo "$PENDING_COUNT" > /tmp/initial_task_count.txt

if [ "$PENDING_COUNT" -eq 0 ]; then
    echo "ERROR: Validation task did not appear."
    exit 1
fi

# 7. Prepare Browser
echo "Launching Firefox..."
open_nuxeo_url "$NUXEO_UI" 8

# Log in
nuxeo_login

# Go to home/dashboard
navigate_to "$NUXEO_UI/#!/home"
sleep 2

# Record Start Time
date +%s > /tmp/task_start_time.txt

# Initial Screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="
echo "Workflow ID: $WF_ID"
echo "Document: $DOC_PATH"
echo "Pending tasks: $PENDING_COUNT"