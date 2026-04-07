#!/bin/bash
# Setup script for update_document_thumbnail task

set -e
echo "=== Setting up update_document_thumbnail task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Wait for Nuxeo to be ready
wait_for_nuxeo 180

# 2. Prepare Data Files
DATA_DIR="/home/ga/nuxeo/data"
mkdir -p "$DATA_DIR"

# Source PDF (Main content)
PDF_SOURCE="/workspace/data/annual_report_2023.pdf"
# Fallback if specific file missing
if [ ! -f "$PDF_SOURCE" ]; then
    PDF_SOURCE="/home/ga/nuxeo/data/Annual_Report_2023.pdf"
fi

# Source Image (Thumbnail)
# We'll use a visual image available in the env, e.g., grand_prismatic.jpg, renamed
IMG_SOURCE="/workspace/data/grand_prismatic.jpg"
# Fallback
if [ ! -f "$IMG_SOURCE" ]; then
    # Create a simple valid JPEG if missing (unlikely given env spec)
    convert -size 640x480 gradient:blue-red "$DATA_DIR/report_cover.jpg"
else
    cp "$IMG_SOURCE" "$DATA_DIR/report_cover.jpg"
fi

chown ga:ga "$DATA_DIR/report_cover.jpg"
chmod 644 "$DATA_DIR/report_cover.jpg"

echo "Thumbnail image prepared at: $DATA_DIR/report_cover.jpg"

# 3. Create the Document 'Q3 Marketing Report'
DOC_PATH="/default-domain/workspaces/Projects/Q3-Marketing-Report"
DOC_NAME="Q3-Marketing-Report"
DOC_TITLE="Q3 Marketing Report"

# Check if doc exists, delete if it does to ensure clean state
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -u "$NUXEO_AUTH" "$NUXEO_URL/api/v1/path$DOC_PATH")
if [ "$HTTP_CODE" == "200" ]; then
    echo "Document exists, deleting to reset..."
    curl -s -u "$NUXEO_AUTH" -X DELETE "$NUXEO_URL/api/v1/path$DOC_PATH"
    sleep 2
fi

# Upload PDF Blob
echo "Uploading PDF content..."
BATCH_ID=$(curl -s -u "$NUXEO_AUTH" -X POST "$NUXEO_URL/api/v1/upload/" | python3 -c "import sys, json; print(json.load(sys.stdin).get('batchId'))")

curl -s -u "$NUXEO_AUTH" -X POST "$NUXEO_URL/api/v1/upload/$BATCH_ID/0" \
    -H "Content-Type: application/octet-stream" \
    -H "X-File-Name: Q3_Marketing_Report.pdf" \
    -H "X-File-Type: application/pdf" \
    --data-binary @"$PDF_SOURCE" > /dev/null

# Create Document with Blob
echo "Creating document..."
PAYLOAD=$(cat <<EOF
{
  "entity-type": "document",
  "type": "File",
  "name": "$DOC_NAME",
  "properties": {
    "dc:title": "$DOC_TITLE",
    "dc:description": "Quarterly marketing performance metrics.",
    "file:content": {
      "upload-batch": "$BATCH_ID",
      "upload-fileId": "0"
    }
  }
}
EOF
)

curl -s -u "$NUXEO_AUTH" -H "Content-Type: application/json" \
    -X POST "$NUXEO_URL/api/v1/path/default-domain/workspaces/Projects" \
    -d "$PAYLOAD" > /dev/null

sleep 2

# 4. Record Initial State (Digests)
# Get the document state
DOC_JSON=$(curl -s -u "$NUXEO_AUTH" -H "X-NXproperties: *" "$NUXEO_URL/api/v1/path$DOC_PATH")
INITIAL_PDF_DIGEST=$(echo "$DOC_JSON" | python3 -c "import sys, json; print(json.load(sys.stdin).get('properties', {}).get('file:content', {}).get('digest', ''))")

# Get the local image digest (MD5 to match Nuxeo's default)
LOCAL_IMG_DIGEST=$(md5sum "$DATA_DIR/report_cover.jpg" | awk '{print $1}')

# Save to tmp file for verifier/export script
cat <<EOF > /tmp/task_initial_state.json
{
  "initial_pdf_digest": "$INITIAL_PDF_DIGEST",
  "target_thumbnail_digest": "$LOCAL_IMG_DIGEST",
  "doc_path": "$DOC_PATH"
}
EOF

echo "Initial state recorded."

# 5. Launch Application
# Open Firefox, login, and navigate to the document
echo "Launching Firefox..."
open_nuxeo_url "$NUXEO_URL/login.jsp" 10

# Perform login if not already logged in
PAGE_TITLE=$(ga_x "xdotool getactivewindow getwindowname" 2>/dev/null || echo "")
if [[ "$PAGE_TITLE" != *"Nuxeo"* ]]; then
    nuxeo_login
fi

# Navigate directly to the document
echo "Navigating to document..."
navigate_to "$NUXEO_UI/#!/browse$DOC_PATH"

# Take initial screenshot
ga_x "scrot /tmp/task_initial.png" 2>/dev/null || true

echo "=== Setup complete ==="