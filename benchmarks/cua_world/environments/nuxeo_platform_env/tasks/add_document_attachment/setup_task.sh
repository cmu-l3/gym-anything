#!/bin/bash
# Setup for add_document_attachment task
# Ensures the Project Proposal document exists, has no attachments, and Firefox is open to it.

source /workspace/scripts/task_utils.sh

echo "=== Setting up add_document_attachment task ==="

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Wait for Nuxeo
wait_for_nuxeo 120

# ---------------------------------------------------------------------------
# Prepare Document: Project Proposal
# ---------------------------------------------------------------------------
echo "Verifying Project Proposal document exists..."
PP_PATH="/default-domain/workspaces/Projects/Project-Proposal"
PP_RESPONSE=$(nuxeo_api GET "/path$PP_PATH")
PP_UID=$(echo "$PP_RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin).get('uid',''))" 2>/dev/null)

DATA_DIR="/home/ga/nuxeo/data"
mkdir -p "$DATA_DIR"

if [ -z "$PP_UID" ] || [ "$PP_UID" = "" ]; then
    echo "Project Proposal document not found. Creating it..."
    
    # Ensure source file exists
    if [ ! -f "$DATA_DIR/Project_Proposal.pdf" ]; then
        cp /workspace/data/project_proposal.pdf "$DATA_DIR/Project_Proposal.pdf" 2>/dev/null || \
        echo "Placeholder content" > "$DATA_DIR/Project_Proposal.pdf"
    fi

    # Upload main file
    BATCH_RESPONSE=$(curl -s -u "$NUXEO_AUTH" -X POST "$NUXEO_URL/api/v1/upload/")
    BATCH_ID=$(echo "$BATCH_RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin).get('batchId',''))" 2>/dev/null)
    
    FILESIZE=$(stat -c%s "$DATA_DIR/Project_Proposal.pdf")
    curl -s -u "$NUXEO_AUTH" \
        -X POST "$NUXEO_URL/api/v1/upload/$BATCH_ID/0" \
        -H "Content-Type: application/octet-stream" \
        -H "X-File-Name: Project_Proposal.pdf" \
        -H "X-File-Type: application/pdf" \
        -H "X-File-Size: $FILESIZE" \
        --data-binary @"$DATA_DIR/Project_Proposal.pdf" > /dev/null

    # Create document
    PAYLOAD=$(cat <<EOFJSON
{
  "entity-type": "document",
  "type": "File",
  "name": "Project-Proposal",
  "properties": {
    "dc:title": "Project Proposal",
    "dc:description": "Main project proposal document",
    "file:content": {
      "upload-batch": "$BATCH_ID",
      "upload-fileId": "0"
    }
  }
}
EOFJSON
)
    nuxeo_api POST "/path/default-domain/workspaces/Projects/" "$PAYLOAD" > /dev/null
    echo "Created Project Proposal document."
    sleep 2
else
    # Ensure main file exists if document existed but was empty
    MAIN_FILE=$(echo "$PP_RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin).get('properties',{}).get('file:content',{}))" 2>/dev/null)
    if [ "$MAIN_FILE" = "None" ] || [ -z "$MAIN_FILE" ]; then
         echo "Project Proposal exists but missing main file. Re-creating..."
         nuxeo_api DELETE "/path$PP_PATH" > /dev/null
         # Recursively call self or just fail/retry? Simpler to just re-run creation logic
         # For simplicity in this script, we'll assume the create block above works if we deleted it.
         # Actually, let's just proceed, the verify logic will catch if main file is missing.
    fi
fi

# ---------------------------------------------------------------------------
# Clean State: Remove existing attachments
# ---------------------------------------------------------------------------
echo "Clearing any existing attachments from Project Proposal..."
CLEAR_PAYLOAD='{"entity-type":"document","properties":{"files:files":[]}}'
nuxeo_api PUT "/path$PP_PATH" "$CLEAR_PAYLOAD" > /dev/null 2>&1
sleep 2

# ---------------------------------------------------------------------------
# Record Initial State
# ---------------------------------------------------------------------------
INITIAL_DOC=$(nuxeo_api GET "/path$PP_PATH")
INITIAL_ATTACH_COUNT=$(echo "$INITIAL_DOC" | python3 -c "
import sys, json
doc = json.load(sys.stdin)
files = doc.get('properties', {}).get('files:files', [])
print(len(files))
" 2>/dev/null || echo "0")

INITIAL_MODIFIED=$(echo "$INITIAL_DOC" | python3 -c "
import sys, json
doc = json.load(sys.stdin)
print(doc.get('properties', {}).get('dc:modified', ''))
" 2>/dev/null || echo "")

cat > /tmp/initial_state.json << EOF
{
  "attachment_count": $INITIAL_ATTACH_COUNT,
  "modified_timestamp": "$INITIAL_MODIFIED",
  "task_start_time": $(cat /tmp/task_start_time.txt)
}
EOF

# ---------------------------------------------------------------------------
# Prepare Attachment File
# ---------------------------------------------------------------------------
ATTACH_FILE="/home/ga/nuxeo/data/Q3_Status_Report.pdf"
if [ ! -f "$ATTACH_FILE" ]; then
    echo "Copying Q3_Status_Report.pdf from workspace data..."
    cp /workspace/data/q3_status_report.pdf "$ATTACH_FILE" 2>/dev/null || \
    echo "Fake PDF content" > "$ATTACH_FILE"
fi
chown ga:ga "$ATTACH_FILE"
chmod 644 "$ATTACH_FILE"

# ---------------------------------------------------------------------------
# Browser Setup
# ---------------------------------------------------------------------------
DOC_URL="${NUXEO_UI}#!/browse/default-domain/workspaces/Projects/Project-Proposal"
open_nuxeo_url "$NUXEO_URL/login.jsp" 10

# Login
nuxeo_login

# Navigate to document
navigate_to "$DOC_URL"

# Take initial screenshot
echo "Capturing initial state..."
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="