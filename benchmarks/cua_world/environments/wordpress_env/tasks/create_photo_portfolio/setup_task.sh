#!/bin/bash
# Setup script for create_photo_portfolio task (pre_task hook)

echo "=== Setting up create_photo_portfolio task ==="

# Source utility functions
source /workspace/scripts/task_utils.sh

# Record baseline counts for attachments and pages
INITIAL_ATTACHMENTS=$(wp_db_query "SELECT COUNT(*) FROM wp_posts WHERE post_type='attachment' AND post_mime_type LIKE 'image/%'" 2>/dev/null || echo "0")
INITIAL_PAGES=$(wp_db_query "SELECT COUNT(*) FROM wp_posts WHERE post_type='page'" 2>/dev/null || echo "0")

echo "$INITIAL_ATTACHMENTS" | sudo tee /tmp/initial_attachments > /dev/null
echo "$INITIAL_PAGES" | sudo tee /tmp/initial_pages > /dev/null
sudo chmod 666 /tmp/initial_attachments /tmp/initial_pages

echo "Baseline: $INITIAL_ATTACHMENTS attachments, $INITIAL_PAGES pages"

# Create Photos directory
PHOTO_DIR="/home/ga/Photos"
sudo -u ga mkdir -p "$PHOTO_DIR"

# Download 5 real photographs from Unsplash/Lorem Picsum
echo "Downloading sample photographs..."
IMAGES=(
    "city-skyline.jpg:1018"
    "street-market.jpg:1033"
    "bridge-sunset.jpg:1039"
    "historic-building.jpg:1044"
    "park-fountain.jpg:1029"
)

for img_data in "${IMAGES[@]}"; do
    filename="${img_data%%:*}"
    id="${img_data##*:}"
    filepath="$PHOTO_DIR/$filename"
    
    echo "Downloading $filename (ID $id)..."
    sudo -u ga curl -sL "https://picsum.photos/id/$id/1024/768" -o "$filepath"
    
    # Check if download succeeded and is a valid image, otherwise generate fallback
    if [ ! -s "$filepath" ] || ! file "$filepath" | grep -qi "image"; then
        echo "WARNING: Download failed or invalid image, generating fallback for $filename"
        sudo apt-get install -y imagemagick > /dev/null 2>&1 || true
        sudo -u ga convert -size 1024x768 xc:gray -font DejaVu-Sans -pointsize 72 -gravity center -draw "text 0,0 'Photo: $filename'" "$filepath" 2>/dev/null || \
        sudo -u ga touch "$filepath" # Ultimate fallback if imagemagick fails
    fi
done

sudo chown -R ga:ga "$PHOTO_DIR"
sudo chmod -R 644 "$PHOTO_DIR"/*
sudo chmod 755 "$PHOTO_DIR"

echo "Photos ready in $PHOTO_DIR:"
ls -l "$PHOTO_DIR"

# Ensure Firefox is running and focused on WordPress admin
echo "Checking Firefox status..."
if ! pgrep -x "firefox" > /dev/null 2>&1; then
    echo "Firefox not running, starting..."
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

# Record task start time
date +%s > /tmp/task_start_time
chmod 666 /tmp/task_start_time

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="