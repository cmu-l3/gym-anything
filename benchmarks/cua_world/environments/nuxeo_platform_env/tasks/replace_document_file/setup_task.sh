#!/bin/bash
# pre_task hook for replace_document_file task.
# Sets up the initial document state and records the initial blob digest.

set -e
echo "=== Setting up replace_document_file task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure Nuxeo is ready
wait_for_nuxeo 120

# 1. Define paths and data
DOC_PATH="/default-domain/workspaces/Templates/Contract-Template"
ORIGINAL_FILE="/home/ga/nuxeo/data/Contract_Template.pdf" # This should exist from env setup
REPLACEMENT_FILE="/home/ga/nuxeo/data/Q3_Status_Report.pdf"

# Ensure replacement file exists (critical for task)
if [ ! -f "$REPLACEMENT_FILE" ]; then
    echo "ERROR: Replacement file $REPLACEMENT_FILE not found."
    # Create dummy if missing (fallback)
    mkdir -p /home/ga/nuxeo/data
    echo "Dummy Q3 Report Content" > "$REPLACEMENT_FILE"
fi

# Ensure original file exists for reset
if [ ! -f "$ORIGINAL_FILE" ]; then
    echo "WARNING: Original file not found, using dummy."
    mkdir -p /home/ga/nuxeo/data
    echo "Original Contract Content" > "$ORIGINAL_FILE"
fi

# 2. Reset the document to known initial state
# Check if doc exists
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -u "$NUXEO_AUTH" "$NUXEO_URL/api/v1/path$DOC_PATH")

if [ "$HTTP_CODE" = "200" ]; then
    echo "Document exists. Deleting to ensure clean state..."
    curl -s -u "$NUXEO_AUTH" -X DELETE "$NUXEO_URL/api/v1/path$DOC_PATH" > /dev/null
fi

# Create the document with the ORIGINAL file
echo "Creating initial 'Contract Template' document..."

# Upload batch
BATCH_RESP=$(curl -s -u "$NUXEO_AUTH" -X POST "$NUXEO_URL/api/v1/upload/")
BATCH_ID=$(echo "$BATCH_RESP" | python3 -c "import sys,json; print(json.load(sys.stdin).get('batchId',''))")

# Upload original file
curl -s -u "$NUXEO_AUTH" -X POST "$NUXEO_URL/api/v1/upload/$BATCH_ID/0" \
    -H "Content-Type: application/octet-stream" \
    -H "X-File-Name: Contract_Template.pdf" \
    -H "X-File-Type: application/pdf" \
    --data-binary @"$ORIGINAL_FILE" > /dev/null

# Create Document
PAYLOAD='{
  "entity-type": "document",
  "type": "File",
  "name": "Contract-Template",
  "properties": {
    "dc:title": "Contract Template",
    "dc:description": "Standard service agreement template v1.0",
    "file:content": {
      "upload-batch": "'"$BATCH_ID"'",
      "upload-fileId": "0"
    }
  }
}'

curl -s -u "$NUXEO_AUTH" -H "Content-Type: application/json" \
    -X POST "$NUXEO_URL/api/v1/path/default-domain/workspaces/Templates" \
    -d "$PAYLOAD" > /dev/null

echo "Document created."
sleep 2

# 3. Record Initial State (Digest)
DOC_JSON=$(curl -s -u "$NUXEO_AUTH" "$NUXEO_URL/api/v1/path$DOC_PATH")
INITIAL_DIGEST=$(echo "$DOC_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin).get('properties',{}).get('file:content',{}).get('digest',''))")
echo "$INITIAL_DIGEST" > /tmp/initial_digest.txt
echo "Initial digest recorded: $INITIAL_DIGEST"

# 4. Open Firefox to the specific document
echo "Launching Firefox..."
open_nuxeo_url "$NUXEO_URL/login.jsp" 8

# Automate login
nuxeo_login

# Navigate to the document
navigate_to "$NUXEO_UI/#!/browse$DOC_PATH"

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="