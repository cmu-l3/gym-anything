#!/bin/bash
set -e

echo "=== Setting up Identify Approved Asset task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure Nuxeo is ready
wait_for_nuxeo 180

# ---------------------------------------------------------------------------
# 1. Setup Data Directory and Generate Images
# ---------------------------------------------------------------------------
DATA_DIR="/tmp/nuxeo_task_data"
rm -rf "$DATA_DIR"
mkdir -p "$DATA_DIR"

echo "Generating asset images using ImageMagick..."

# Generate 'Approved' image (Red stamp)
convert -size 600x400 xc:white \
    -fill "#F0F0F0" -draw "rectangle 20,20 580,380" \
    -fill red -pointsize 60 -gravity center -draw "text 0,0 'APPROVED'" \
    -bordercolor black -border 5 \
    "$DATA_DIR/img_approved.jpg"

# Generate 'Draft' image (Grey text)
convert -size 600x400 xc:white \
    -fill "#F0F0F0" -draw "rectangle 20,20 580,380" \
    -fill grey -pointsize 60 -gravity center -draw "text 0,0 'DRAFT v1'" \
    -bordercolor black -border 5 \
    "$DATA_DIR/img_draft.jpg"

chown -R ga:ga "$DATA_DIR"

# ---------------------------------------------------------------------------
# 2. Setup Nuxeo Workspace
# ---------------------------------------------------------------------------
echo "Creating workspace..."
# We use the REST API to ensure a clean state for the workspace
# First, try to delete it if it exists to clean up previous runs
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -u "$NUXEO_AUTH" \
    "$NUXEO_URL/api/v1/path/default-domain/workspaces/Campaign-Assets")

if [ "$HTTP_CODE" = "200" ]; then
    echo "Workspace exists, cleaning up..."
    curl -s -u "$NUXEO_AUTH" -X DELETE "$NUXEO_URL/api/v1/path/default-domain/workspaces/Campaign-Assets"
    sleep 2
fi

# Create the workspace
create_doc_if_missing "/default-domain/workspaces" "Workspace" "Campaign-Assets" "Campaign Assets" "Review pending marketing assets"
sleep 2

# ---------------------------------------------------------------------------
# 3. Randomize and Upload Documents
# ---------------------------------------------------------------------------
echo "Uploading documents..."

# Random selection: 0 = Alpha is Approved, 1 = Beta is Approved
RAND=$((RANDOM % 2))

if [ "$RAND" -eq 0 ]; then
    echo "Configuration: Alpha = APPROVED, Beta = DRAFT"
    PATH_ALPHA="$DATA_DIR/img_approved.jpg"
    PATH_BETA="$DATA_DIR/img_draft.jpg"
    CORRECT_DOC="Candidate-Alpha"
else
    echo "Configuration: Alpha = DRAFT, Beta = APPROVED"
    PATH_ALPHA="$DATA_DIR/img_draft.jpg"
    PATH_BETA="$DATA_DIR/img_approved.jpg"
    CORRECT_DOC="Candidate-Beta"
fi

# Helper to upload file and create document
upload_doc() {
    local doc_name="$1"
    local file_path="$2"
    local title="$doc_name"
    
    local filename=$(basename "$file_path")
    local filesize=$(stat -c%s "$file_path")
    
    # 1. Upload Batch
    local batch_resp
    batch_resp=$(curl -s -u "$NUXEO_AUTH" -X POST "$NUXEO_URL/api/v1/upload/")
    local batch_id
    batch_id=$(echo "$batch_resp" | python3 -c "import sys,json; print(json.load(sys.stdin).get('batchId',''))")
    
    curl -s -u "$NUXEO_AUTH" -X POST "$NUXEO_URL/api/v1/upload/$batch_id/0" \
        -H "Content-Type: application/octet-stream" \
        -H "X-File-Name: $filename" \
        -H "X-File-Type: image/jpeg" \
        -H "X-File-Size: $filesize" \
        --data-binary @"$file_path" > /dev/null

    # 2. Create Document
    local payload
    payload=$(cat <<EOFJSON
{
  "entity-type": "document",
  "type": "File",
  "name": "$doc_name",
  "properties": {
    "dc:title": "$title",
    "file:content": {
      "upload-batch": "$batch_id",
      "upload-fileId": "0"
    }
  }
}
EOFJSON
)
    # Return the UID
    nuxeo_api POST "/path/default-domain/workspaces/Campaign-Assets/" "$payload" \
        | python3 -c "import sys,json; print(json.load(sys.stdin).get('uid',''))"
}

UID_ALPHA=$(upload_doc "Candidate-Alpha" "$PATH_ALPHA")
UID_BETA=$(upload_doc "Candidate-Beta" "$PATH_BETA")

# Determine which UID is the correct one (Approved) and which is the wrong one (Draft)
if [ "$RAND" -eq 0 ]; then
    CORRECT_UID="$UID_ALPHA"
    WRONG_UID="$UID_BETA"
else
    CORRECT_UID="$UID_BETA"
    WRONG_UID="$UID_ALPHA"
fi

# Save Ground Truth for verification (hidden from agent)
cat <<EOF > /tmp/ground_truth.json
{
    "correct_uid": "$CORRECT_UID",
    "wrong_uid": "$WRONG_UID",
    "correct_doc_name": "$CORRECT_DOC",
    "random_seed": $RAND
}
EOF
chmod 644 /tmp/ground_truth.json

echo "Ground truth saved. Correct Doc: $CORRECT_DOC (UID: $CORRECT_UID)"

# ---------------------------------------------------------------------------
# 4. Launch Browser
# ---------------------------------------------------------------------------
# Open Nuxeo in Firefox
open_nuxeo_url "$NUXEO_UI/#!/browse/default-domain/workspaces/Campaign-Assets" 10

# Automate login
nuxeo_login

# Ensure window is maximized for the agent
DISPLAY=:1 wmctrl -r "Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Capture initial screenshot
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="