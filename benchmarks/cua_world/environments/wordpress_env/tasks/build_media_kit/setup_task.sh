#!/bin/bash
# Setup script for build_media_kit task (pre_task hook)

echo "=== Setting up build_media_kit task ==="

source /workspace/scripts/task_utils.sh

# Record task start timestamp
date +%s > /tmp/task_start_timestamp
chmod 666 /tmp/task_start_timestamp

# Record initial attachment count
INITIAL_ATTACHMENTS=$(wp_db_query "SELECT COUNT(*) FROM wp_posts WHERE post_type='attachment'")
echo "$INITIAL_ATTACHMENTS" | sudo tee /tmp/initial_attachment_count > /dev/null
sudo chmod 666 /tmp/initial_attachment_count

# Ensure target directory exists
MEDIA_DIR="/home/ga/Documents/MediaKit"
mkdir -p "$MEDIA_DIR"

# Generate valid minimal files using base64 to ensure they are available offline
# 1. Minimal PDF
echo "JVBERi0xLjQKJcOkw7zDtsOfCjIgMCBvYmoKPDwvTGVuZ3RoIDMgMCBSL0ZpbHRlci9GbGF0ZURlY29kZT4+CnN0cmVhbQp4nDPQM1Qo5ypUMFAwALJMLU31jBQsTAz1DBSM/FzB/PzEvBQF18xUBaAITcxM2cwUQj0VTA0UwhKLU4v0nEtyUvNyKvkAg6sQtgplbmRzdHJlYW0KZW5kb2JqCgozIDAgb2JqCjY5CmVuZG9iagoKNCAwIG9iago8PC9UeXBlL1BhZ2UvTWVkaWFCb3ggWzAgMCA1OTUuMjggODQxLjg5XS9SZXNvdXJjZXM8PC9Gb250PDwvRjEgNSAwIFI+Pj4+L0NvbnRlbnRzIDIgMCBSL1BhcmVudCA2IDAgUj4+CmVuZG9iagoKNSAwIG9iago8PC9UeXBlL0ZvbnQvU3VidHlwZS9UeXBlMS9CYXNlRm9udC9IZWx2ZXRpY2E+PgplbmRvYmoKCjYgMCBvYmoKPDwvVHlwZS9QYWdlcy9Db3VudCAxL0tpZHNbNCAwIFJdPj4KZW5kb2JqCgoxIDAgb2JqCjw8L1R5cGUvQ2F0YWxvZy9QYWdlcyA2IDAgUj4+CmVuZG9iagoKeHJlZgowIDcKMDAwMDAwMDAwMCA2NTUzNSBmIAowMDAwMDAwMzg3IDAwMDAwIG4gCjAwMDAwMDAwMTUgMDAwMDAgbiAKMDAwMDAwMDE1NSAwMDAwMCBuIAowMDAwMDAwMTc0IDAwMDAwIG4gCjAwMDAwMDAyOTIgMDAwMDAgbiAKMDAwMDAwMDMzMCAwMDAwMCBuIAp0cmFpbGVyCjw8L1NpemUgNy9Sb290IDEgMCBSPj4Kc3RhcnR4cmVmCjQzNgolJUVPRgo=" | base64 -d > "$MEDIA_DIR/Nimbus_Press_Release.pdf"

# 2. Minimal ZIP
echo "UEsDBAoAAAAAADBcZlkAAAAAAAAAAAAAAAAIAAAAdGVzdC50eHRQSwcCAAAAAAMAAAAAAAAAUEsBAgMACgAAAAAAMFxmWQAAAAAAAAAAAAAAAACAAAAHAAAAAAAAAAAAAAAAAAAAAAB0ZXN0LnR4dFBLBQYAAAAAAQABADYAAAAiAAAAAAA=" | base64 -d > "$MEDIA_DIR/Nimbus_Brand_Assets.zip"

# 3. Minimal valid JPG (1x1 white pixel)
echo "/9j/4AAQSkZJRgABAQEASABIAAD/2wBDAP//////////////////////////////////////////////////////////////////////////////////////wgALCAABAAEBAREA/8QAFBABAAAAAAAAAAAAAAAAAAAAAP/aAAgBAQABPxA=" | base64 -d > "$MEDIA_DIR/CEO_Portrait.jpg"

chown -R ga:ga "$MEDIA_DIR"
chmod 644 "$MEDIA_DIR"/*

# Ensure Firefox is running and focused on WordPress admin
echo "Checking Firefox status..."
if ! pgrep -x "firefox" > /dev/null 2>&1; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox 'http://localhost/wp-admin/' > /tmp/firefox_restart.log 2>&1 &"
    sleep 10
fi

# Focus Firefox window
WID=$(DISPLAY=:1 wmctrl -l | grep -i "firefox\|mozilla\|wordpress" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
fi

take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="
echo "Files ready in ~/Documents/MediaKit/"