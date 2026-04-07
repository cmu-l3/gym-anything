#!/bin/bash
set -e
echo "=== Setting up cancel_stalled_workflow task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Ensure Nuxeo is ready
wait_for_nuxeo 180

# 2. Ensure Document Exists (Contract Template)
# We check if it exists, if not we create it using the utility function
if ! doc_exists "/default-domain/workspaces/Templates/Contract-Template"; then
    echo "Creating Contract Template..."
    # Ensure parent folder exists
    if ! doc_exists "/default-domain/workspaces/Templates"; then
        create_doc_if_missing "/default-domain/workspaces" "Workspace" "Templates" "Templates"
    fi
    
    # Upload/Create the file
    # We'll just create a placeholder file document for simplicity if the PDF isn't handy, 
    # but ideally we use the real file. 
    # The setup_nuxeo.sh usually copies data to /home/ga/nuxeo/data/
    PDF_PATH="/home/ga/nuxeo/data/Contract_Template.pdf"
    if [ ! -f "$PDF_PATH" ]; then
         # Fallback to creating a dummy file
         echo "Dummy PDF content" > /tmp/contract.pdf
         PDF_PATH="/tmp/contract.pdf"
    fi
    
    # We use a simple create_doc here, uploading is complex in bash without the helper in setup_nuxeo.sh
    # But let's use the create_doc_if_missing which makes a simple doc without content if needed, 
    # or we can use the Automation API to attach a blob later.
    # For this task, the BLOB content doesn't matter, just the Document object and Workflow.
    create_doc_if_missing "/default-domain/workspaces/Templates" "File" "Contract-Template" "Contract Template" "Standard template"
fi

# Get Document UID
DOC_ID=$(nuxeo_api GET "/path/default-domain/workspaces/Templates/Contract-Template" | python3 -c "import sys,json; print(json.load(sys.stdin).get('uid',''))")
echo "Target Document ID: $DOC_ID"
echo "$DOC_ID" > /tmp/target_doc_id.txt

# 3. Create user 'jsmith' if missing
echo "Ensuring user jsmith exists..."
if ! nuxeo_api GET "/user/jsmith" | grep -q "jsmith"; then
    USER_PAYLOAD='{"entity-type":"user","id":"jsmith","properties":{"username":"jsmith","password":"password123","firstName":"John","lastName":"Smith","email":"jsmith@example.com","groups":["members"]}}'
    nuxeo_api POST "/user" "$USER_PAYLOAD" > /dev/null
fi

# 4. Start 'Serial Document Review' Workflow
echo "Starting workflow..."

# Check if workflow already active
EXISTING_TASKS=$(nuxeo_api GET "/task?targetDocumentId=$DOC_ID&isCompleted=false" | python3 -c "import sys,json; print(len(json.load(sys.stdin).get('entries',[])))")

if [ "$EXISTING_TASKS" -eq "0" ]; then
    # Start workflow via Automation API
    # Operation: Context.StartWorkflow
    WORKFLOW_PAYLOAD=$(cat <<EOF
{
  "params": {
    "id": "SerialDocumentReview",
    "start": true
  },
  "context": {
    "workflowVariables": {
      "participants": ["user:jsmith"],
      "validationOrReview": "simpleReview"
    }
  },
  "input": "$DOC_ID"
}
EOF
)
    RESPONSE=$(curl -s -u "$NUXEO_AUTH" \
        -H "Content-Type: application/json" \
        -X POST "$NUXEO_URL/api/v1/automation/Context.StartWorkflow" \
        -d "$WORKFLOW_PAYLOAD")
    
    # Capture Workflow ID
    WORKFLOW_ID=$(echo "$RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin).get('id',''))")
    echo "Started Workflow ID: $WORKFLOW_ID"
    echo "$WORKFLOW_ID" > /tmp/initial_workflow_id.txt
else
    echo "Workflow already active."
    # Try to find the existing workflow ID from the task
    nuxeo_api GET "/task?targetDocumentId=$DOC_ID&isCompleted=false" | python3 -c "import sys,json; print(json.load(sys.stdin).get('entries',[{}])[0].get('workflowInstanceId',''))" > /tmp/initial_workflow_id.txt
fi

# 5. Open Firefox to Nuxeo Home
open_nuxeo_url "$NUXEO_URL/login.jsp" 8
nuxeo_login

# 6. Capture Initial State
echo "Capturing initial state..."
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="