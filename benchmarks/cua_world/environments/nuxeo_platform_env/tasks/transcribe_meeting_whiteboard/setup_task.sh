#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up task: transcribe_meeting_whiteboard@1 ==="

# Record start time
date +%s > /tmp/task_start_time.txt

# 1. Generate Dynamic Data (Anti-Gaming)
# Generate a random project code and budget to stamp on the image
RANDOM_ID=$((1000 + RANDOM % 8999))
PROJ_CODE="PROJ-${RANDOM_ID}"
BUDGET="\$${RANDOM_ID}00"
echo "Generated Project Code: $PROJ_CODE"

# Save ground truth for export/verification (hidden location)
mkdir -p /var/lib/nuxeo/ground_truth
echo "$PROJ_CODE" > /var/lib/nuxeo/ground_truth/secret_code.txt
chmod 644 /var/lib/nuxeo/ground_truth/secret_code.txt

# 2. Create the Whiteboard Image
IMAGE_DIR="/home/ga/nuxeo/data"
mkdir -p "$IMAGE_DIR"
IMAGE_PATH="$IMAGE_DIR/whiteboard_scan.jpg"

echo "Generating whiteboard image..."

# Create a white background with some noise to look like a whiteboard
convert -size 1024x768 xc:white \
    -fill "gray98" -draw "rectangle 0,0 1024,768" \
    -noise 2 \
    "$IMAGE_PATH"

# Add "Handwritten" Text
# Using standard fonts available in container (DejaVu-Sans)
convert "$IMAGE_PATH" \
    -pointsize 42 -fill "darkblue" -font "DejaVu-Sans-Bold" \
    -draw "text 50,80 'Strategy Session - Q3'" \
    -pointsize 32 -fill "black" -font "DejaVu-Sans" \
    -draw "text 50,180 'Project Code: $PROJ_CODE'" \
    -draw "text 50,250 'Action Items:'" \
    -draw "text 80,320 '- Hire Backend Lead'" \
    -draw "text 80,380 '- Finalize Budget: $BUDGET'" \
    -draw "text 80,440 '- Launch Beta by Nov 1'" \
    -fill "darkred" \
    -draw "text 600,600 'DO NOT ERASE!'" \
    -rotate 1 \
    "$IMAGE_PATH"

chown ga:ga "$IMAGE_PATH"
echo "Created whiteboard image at $IMAGE_PATH"

# 3. Setup Nuxeo State
wait_for_nuxeo 180

# Create Projects workspace if not exists
if ! doc_exists "/default-domain/workspaces/Projects"; then
    create_doc_if_missing "/default-domain/workspaces" "Workspace" "Projects" \
        "Projects" "Active project documents"
fi

# Clean up previous runs
# Remove the Note if it exists
curl -s -u "$NUXEO_AUTH" -X DELETE \
    "$NUXEO_URL/api/v1/path/default-domain/workspaces/Projects/Strategy-Meeting-Notes" 2>/dev/null || true
# Remove the Image if it exists
curl -s -u "$NUXEO_AUTH" -X DELETE \
    "$NUXEO_URL/api/v1/path/default-domain/workspaces/Projects/Whiteboard-Capture" 2>/dev/null || true

# Upload the Whiteboard Image
echo "Uploading image to Nuxeo..."
BATCH_RESPONSE=$(curl -s -u "$NUXEO_AUTH" -X POST "$NUXEO_URL/api/v1/upload/")
BATCH_ID=$(echo "$BATCH_RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin).get('batchId',''))")

if [ -n "$BATCH_ID" ]; then
    curl -s -u "$NUXEO_AUTH" \
        -X POST "$NUXEO_URL/api/v1/upload/$BATCH_ID/0" \
        -H "Content-Type: image/jpeg" \
        -H "X-File-Name: whiteboard_scan.jpg" \
        -H "X-File-Type: image/jpeg" \
        --data-binary @"$IMAGE_PATH" > /dev/null

    PAYLOAD=$(cat <<EOF
{
  "entity-type": "document",
  "type": "File",
  "name": "Whiteboard-Capture",
  "properties": {
    "dc:title": "Whiteboard-Capture",
    "dc:description": "Photo of the strategy meeting whiteboard",
    "file:content": {
      "upload-batch": "$BATCH_ID",
      "upload-fileId": "0"
    }
  }
}
EOF
)
    nuxeo_api POST "/path/default-domain/workspaces/Projects/" "$PAYLOAD" > /dev/null
    echo "Uploaded Whiteboard-Capture to Projects."
else
    echo "ERROR: Failed to get upload batch ID"
    exit 1
fi

# 4. Prepare Browser
# Open Firefox to the Projects workspace
open_nuxeo_url "$NUXEO_UI/#!/browse/default-domain/workspaces/Projects" 10
nuxeo_login

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="