#!/bin/bash
set -e
echo "=== Setting up download_picture_rendition task ==="

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

source /workspace/scripts/task_utils.sh

# 1. Wait for Nuxeo to be ready
wait_for_nuxeo 180

# 2. Prepare Download Directory
mkdir -p /home/ga/Downloads
rm -f /home/ga/Downloads/event_medium.jpg
chown -R ga:ga /home/ga/Downloads

# 3. Create 'Assets' Workspace
echo "Creating Assets workspace..."
if ! doc_exists "/default-domain/workspaces/Assets"; then
    create_doc_if_missing "/default-domain/workspaces" "Workspace" "Assets" "Assets" "Marketing assets"
fi

# 4. Prepare High-Res Data
# Download a real high-res image (~4000px wide)
IMG_URL="https://upload.wikimedia.org/wikipedia/commons/8/82/Paranal_Platform_After_Sunset_%28ESO%29.jpg"
IMG_PATH="/tmp/high_res.jpg"

echo "Downloading high-res image..."
if [ ! -f "$IMG_PATH" ]; then
    wget -q -O "$IMG_PATH" "$IMG_URL" || curl -L -s -o "$IMG_PATH" "$IMG_URL"
fi

# Verify image integrity, generate fallback if download failed
if ! file "$IMG_PATH" | grep -q "JPEG"; then
    echo "WARNING: Download failed or invalid. Generating synthetic high-res image..."
    # Create 4000x3000 image
    convert -size 4000x3000 xc:blue -fill white -pointsize 100 -draw "text 1000,1500 'High Res Asset'" "$IMG_PATH"
fi

# 5. Upload as 'Picture' Document
# We use the Batch Upload API + Document Creation to ensure 'Picture' type triggers rendition generation
echo "Uploading Picture asset..."

# Check if document already exists
if ! doc_exists "/default-domain/workspaces/Assets/Launch-Day-Event"; then
    # Start Batch
    BATCH_RESPONSE=$(curl -s -u "$NUXEO_AUTH" -X POST "$NUXEO_URL/api/v1/upload/")
    BATCH_ID=$(echo "$BATCH_RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin).get('batchId',''))" 2>/dev/null)
    
    if [ -n "$BATCH_ID" ]; then
        # Upload File to Batch
        FILESIZE=$(stat -c%s "$IMG_PATH")
        curl -s -u "$NUXEO_AUTH" -X POST "$NUXEO_URL/api/v1/upload/$BATCH_ID/0" \
            -H "Content-Type: application/octet-stream" \
            -H "X-File-Name: high_res.jpg" \
            -H "X-File-Type: image/jpeg" \
            -H "X-File-Size: $FILESIZE" \
            --data-binary @"$IMG_PATH" > /dev/null

        # Create 'Picture' Document linked to batch
        PAYLOAD=$(cat <<EOFJSON
{
  "entity-type": "document",
  "type": "Picture",
  "name": "Launch-Day-Event",
  "properties": {
    "dc:title": "Launch Day Event",
    "dc:description": "High resolution photo from the launch event",
    "file:content": {
      "upload-batch": "$BATCH_ID",
      "upload-fileId": "0"
    }
  }
}
EOFJSON
)
        nuxeo_api POST "/path/default-domain/workspaces/Assets/" "$PAYLOAD" > /dev/null
        echo "Created Picture document 'Launch Day Event'."
        
        # Give Nuxeo a moment to generate renditions (async listener)
        sleep 5
    else
        echo "ERROR: Failed to initialize upload batch."
    fi
else
    echo "Picture document already exists."
fi

# 6. Configure Firefox Preferences
# We want to avoid the "Save As" dialog if possible, or at least default to Downloads
echo "Configuring Firefox preferences..."
pkill -f firefox || true
sleep 1

# Ensure profile exists
if [ ! -d "/home/ga/.mozilla/firefox" ]; then
    su - ga -c "firefox --headless &"
    sleep 5
    pkill -f firefox || true
fi

# Find profile directory
FF_PROFILE=$(find /home/ga/.mozilla/firefox -name "*.default*" -type d | head -n 1)

if [ -n "$FF_PROFILE" ]; then
    cat <<EOF >> "$FF_PROFILE/user.js"
user_pref("browser.download.folderList", 2);
user_pref("browser.download.dir", "/home/ga/Downloads");
user_pref("browser.download.useDownloadDir", true);
user_pref("browser.helperApps.neverAsk.saveToDisk", "image/jpeg,image/png,application/octet-stream");
EOF
    chown -R ga:ga "/home/ga/.mozilla"
fi

# 7. Launch Application
# Open Nuxeo at the Assets workspace
open_nuxeo_url "$NUXEO_UI/#!/browse/default-domain/workspaces/Assets" 10

# Ensure login
sleep 2
PAGE_TITLE=$(DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority \
    xdotool getactivewindow getwindowname 2>/dev/null || echo "")
if ! echo "$PAGE_TITLE" | grep -q " - Nuxeo Platform"; then
    nuxeo_login
fi

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="