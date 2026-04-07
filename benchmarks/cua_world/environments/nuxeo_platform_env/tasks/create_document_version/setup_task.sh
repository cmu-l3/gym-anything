#!/bin/bash
# Setup for create_document_version task
# Ensures the Annual Report 2023 document exists at version 0.0 with no prior versions.

source /workspace/scripts/task_utils.sh

echo "=== Setting up create_document_version task ==="
date +%s > /tmp/task_start_time.txt

# Wait for Nuxeo to be responsive
wait_for_nuxeo 120

DOC_PATH="/default-domain/workspaces/Projects/Annual-Report-2023"
DATA_DIR="/home/ga/nuxeo/data"

# ---------------------------------------------------------------------------
# Helper: Upload the Annual Report PDF and create a fresh File document
# ---------------------------------------------------------------------------
recreate_document() {
    echo "Creating fresh Annual-Report-2023 document..."
    
    # Check if PDF source exists
    LOCAL_PDF="$DATA_DIR/Annual_Report_2023.pdf"
    if [ ! -f "$LOCAL_PDF" ]; then
        # Fallback if data mount missing
        LOCAL_PDF="/tmp/Annual_Report_2023.pdf"
        echo "Placeholder PDF" > "$LOCAL_PDF"
    fi

    BATCH_RESPONSE=$(curl -s -u "$NUXEO_AUTH" -X POST "$NUXEO_URL/api/v1/upload/")
    BATCH_ID=$(echo "$BATCH_RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin).get('batchId',''))" 2>/dev/null)

    if [ -n "$BATCH_ID" ]; then
        filesize=$(stat -c%s "$LOCAL_PDF")
        curl -s -u "$NUXEO_AUTH" \
            -X POST "$NUXEO_URL/api/v1/upload/$BATCH_ID/0" \
            -H "Content-Type: application/octet-stream" \
            -H "X-File-Name: Annual_Report_2023.pdf" \
            -H "X-File-Type: application/pdf" \
            -H "X-File-Size: $filesize" \
            --data-binary @"$LOCAL_PDF" > /dev/null

        PAYLOAD=$(cat <<EOFJSON
{
  "entity-type": "document",
  "type": "File",
  "name": "Annual-Report-2023",
  "properties": {
    "dc:title": "Annual Report 2023",
    "dc:description": "Uploaded document",
    "file:content": {
      "upload-batch": "$BATCH_ID",
      "upload-fileId": "0"
    }
  }
}
EOFJSON
)
        nuxeo_api POST "/path/default-domain/workspaces/Projects/" "$PAYLOAD" > /dev/null
        echo "Recreated Annual Report 2023 with PDF attachment."
    else
        echo "Failed to get upload batch ID"
    fi
}

# ---------------------------------------------------------------------------
# Ensure the document exists and has NO existing versions
# ---------------------------------------------------------------------------
if doc_exists "$DOC_PATH"; then
    # Get document UID to check for versions
    DOC_UID=$(nuxeo_api GET "/path$DOC_PATH" | python3 -c "import sys,json; print(json.load(sys.stdin).get('uid',''))" 2>/dev/null)

    if [ -n "$DOC_UID" ]; then
        # Query for any existing versions
        QUERY="SELECT * FROM Document WHERE ecm:versionVersionableId = '$DOC_UID' AND ecm:isVersion = 1"
        ENCODED_QUERY=$(python3 -c "import urllib.parse; print(urllib.parse.quote(\"$QUERY\"))")
        VERSION_COUNT=$(curl -s -u "$NUXEO_AUTH" \
            "$NUXEO_URL/api/v1/search/lang/NXQL/execute?query=$ENCODED_QUERY" | \
            python3 -c "import sys,json; print(json.load(sys.stdin).get('resultsCount',0))" 2>/dev/null)

        echo "Existing version count: $VERSION_COUNT"

        if [ "$VERSION_COUNT" -gt "0" ] 2>/dev/null; then
            echo "Document has existing versions. Deleting and recreating..."
            # Delete the document (moves to trash)
            curl -s -u "$NUXEO_AUTH" -X DELETE "$NUXEO_URL/api/v1/path$DOC_PATH" > /dev/null 2>&1
            sleep 2
            recreate_document
        else
            echo "Document exists with no versions. Resetting description..."
            nuxeo_api PUT "/path$DOC_PATH" '{
              "entity-type": "document",
              "properties": {
                "dc:description": "Uploaded document"
              }
            }' > /dev/null
        fi
    fi
else
    echo "Document not found. Creating..."
    recreate_document
fi

sleep 3

# ---------------------------------------------------------------------------
# Prepare Browser
# ---------------------------------------------------------------------------
# Open Firefox to the login page first to ensure session
open_nuxeo_url "$NUXEO_URL/login.jsp" 8

# Check if we need to login (if title doesn't indicate logged in)
sleep 3
PAGE_TITLE=$(ga_x "xdotool getactivewindow getwindowname" 2>/dev/null || echo "")
if ! echo "$PAGE_TITLE" | grep -q " - Nuxeo Platform"; then
    nuxeo_login
fi

# Navigate explicitly to the document
DOC_URL="$NUXEO_UI/#!/browse$DOC_PATH"
navigate_to "$DOC_URL"
sleep 2

# Take initial screenshot
echo "Capturing initial state..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="