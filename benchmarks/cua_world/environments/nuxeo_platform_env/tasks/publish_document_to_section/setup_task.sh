#!/bin/bash
# Setup for publish_document_to_section task
source /workspace/scripts/task_utils.sh

echo "=== Setting up publish_document_to_section task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Wait for Nuxeo to be ready
wait_for_nuxeo 180

# 1. Clean up target section (remove any existing documents in Public-Reports)
# We use NXQL to find children and delete them
echo "Cleaning target section..."
CHILDREN_IDS=$(curl -s -u "$NUXEO_AUTH" -H "Content-Type: application/json" \
    "$NUXEO_URL/api/v1/search/lang/NXQL/execute?query=SELECT+*+FROM+Document+WHERE+ecm:path+STARTSWITH+'/default-domain/sections/Public-Reports'+AND+ecm:primaryType!='Section'+AND+ecm:isTrashed=0" \
    | python3 -c "import sys,json; print('\n'.join([d['uid'] for d in json.load(sys.stdin).get('entries', [])]))" 2>/dev/null)

if [ -n "$CHILDREN_IDS" ]; then
    echo "$CHILDREN_IDS" | while read -r uid; do
        if [ -n "$uid" ]; then
            curl -s -u "$NUXEO_AUTH" -X DELETE "$NUXEO_URL/api/v1/id/$uid" >/dev/null
        fi
    done
    echo "Cleaned previous documents from Public Reports."
fi

# 2. Create target section "Public Reports" if it doesn't exist
echo "Ensuring target section 'Public Reports' exists..."
if ! doc_exists "/default-domain/sections/Public-Reports"; then
    SECTION_PAYLOAD='{
      "entity-type": "document",
      "type": "Section",
      "name": "Public-Reports",
      "properties": {
        "dc:title": "Public Reports",
        "dc:description": "Published documents for organizational access"
      }
    }'
    nuxeo_api POST "/path/default-domain/sections/" "$SECTION_PAYLOAD" > /dev/null
    echo "Created 'Public Reports' section."
fi

# 3. Verify/Create source document "Annual Report 2023"
if ! doc_exists "/default-domain/workspaces/Projects/Annual-Report-2023"; then
    echo "Source document missing. Recreating..."
    # Attempt to upload real PDF if available
    PDF_PATH="/workspace/data/annual_report_2023.pdf"
    if [ ! -f "$PDF_PATH" ]; then
        PDF_PATH="/home/ga/nuxeo/data/Annual_Report_2023.pdf"
    fi
    
    if [ -f "$PDF_PATH" ]; then
        BATCH_RESPONSE=$(curl -s -u "$NUXEO_AUTH" -X POST "$NUXEO_URL/api/v1/upload/")
        BATCH_ID=$(echo "$BATCH_RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin).get('batchId',''))" 2>/dev/null)
        
        if [ -n "$BATCH_ID" ]; then
            FSIZE=$(stat -c%s "$PDF_PATH")
            curl -s -u "$NUXEO_AUTH" \
                -X POST "$NUXEO_URL/api/v1/upload/$BATCH_ID/0" \
                -H "Content-Type: application/octet-stream" \
                -H "X-File-Name: Annual_Report_2023.pdf" \
                -H "X-File-Type: application/pdf" \
                -H "X-File-Size: $FSIZE" \
                --data-binary @"$PDF_PATH" > /dev/null

            UPLOAD_PAYLOAD=$(cat <<EOFJSON
{
  "entity-type": "document",
  "type": "File",
  "name": "Annual-Report-2023",
  "properties": {
    "dc:title": "Annual Report 2023",
    "dc:description": "Official annual report.",
    "file:content": {
      "upload-batch": "$BATCH_ID",
      "upload-fileId": "0"
    }
  }
}
EOFJSON
)
            nuxeo_api POST "/path/default-domain/workspaces/Projects/" "$UPLOAD_PAYLOAD" > /dev/null
            echo "Uploaded Annual Report 2023."
        fi
    else
        # Fallback to creating a note if PDF missing
        NOTE_PAYLOAD='{"entity-type":"document","type":"Note","name":"Annual-Report-2023","properties":{"dc:title":"Annual Report 2023","note:note":"Content of the report."}}'
        nuxeo_api POST "/path/default-domain/workspaces/Projects/" "$NOTE_PAYLOAD" > /dev/null
        echo "Created placeholder Annual Report 2023."
    fi
fi

# 4. Record initial state (doc count in section)
# Should be 0 after cleanup
INITIAL_COUNT=0
echo "$INITIAL_COUNT" > /tmp/initial_section_doc_count.txt

# 5. Open Firefox to the source document
# We rely on nuxeo_login to handle auth, but we start at the specific URL to save time
open_nuxeo_url "http://localhost:8080/nuxeo/ui/#!/browse/default-domain/workspaces/Projects/Annual-Report-2023" 10

# Login
nuxeo_login

# Ensure we are definitely on the right page after login redirect
navigate_to "http://localhost:8080/nuxeo/ui/#!/browse/default-domain/workspaces/Projects/Annual-Report-2023"

# Capture initial screenshot
echo "Capturing initial state..."
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="