#!/bin/bash
# Setup script for edit_media_natively_and_scale task (pre_task hook)
# Downloads real high-res media, injects issues (rotation/oversize), and imports to WP Media Library.

echo "=== Setting up edit_media_natively_and_scale task ==="

source /workspace/scripts/task_utils.sh

# Record task start timestamp
date +%s > /tmp/task_start_timestamp
chmod 666 /tmp/task_start_timestamp

# ============================================================
# 1. Download Real Public Domain Images
# ============================================================
echo "Downloading public domain source images..."

# Landscape: ~2272px wide (needs scaling to 1200px)
curl -sL "https://upload.wikimedia.org/wikipedia/commons/3/36/Hopetoun_falls.jpg" -o /tmp/landscape.jpg || \
wget -qO /tmp/landscape.jpg "https://upload.wikimedia.org/wikipedia/commons/3/36/Hopetoun_falls.jpg"

# Portrait: John F. Kennedy Official Portrait
curl -sL "https://upload.wikimedia.org/wikipedia/commons/thumb/4/4e/President_John_F._Kennedy_Official_Portrait.jpg/1024px-President_John_F._Kennedy_Official_Portrait.jpg" -o /tmp/portrait.jpg || \
wget -qO /tmp/portrait.jpg "https://upload.wikimedia.org/wikipedia/commons/thumb/4/4e/President_John_F._Kennedy_Official_Portrait.jpg/1024px-President_John_F._Kennedy_Official_Portrait.jpg"

# ============================================================
# 2. Modify Images for Task Requirements
# ============================================================
echo "Injecting rotation issue into portrait image..."
# Use PHP's GD library (pre-installed for WP) to reliably rotate the image 90 degrees CCW
# This forces the agent to use WordPress "Rotate Right" (90 deg CW) to fix it.
cat > /tmp/rotate.php << 'EOF'
<?php
$im = imagecreatefromjpeg('/tmp/portrait.jpg');
if ($im) {
    // 90 degrees in PHP imagerotate is counter-clockwise
    $rotated = imagerotate($im, 90, 0);
    imagejpeg($rotated, '/tmp/portrait.jpg', 100);
}
?>
EOF
php /tmp/rotate.php

# ============================================================
# 3. Import Media via WP-CLI
# ============================================================
echo "Importing media into WordPress..."
cd /var/www/html/wordpress

# Clean up any previous runs
wp post delete $(wp post list --post_type=attachment --field=ID --allow-root) --force --allow-root 2>/dev/null || true

LANDSCAPE_ID=$(wp media import /tmp/landscape.jpg --title="Massive Landscape" --porcelain --allow-root)
PORTRAIT_ID=$(wp media import /tmp/portrait.jpg --title="Sideways Portrait" --porcelain --allow-root)

echo "$LANDSCAPE_ID" > /tmp/landscape_id.txt
echo "$PORTRAIT_ID" > /tmp/portrait_id.txt
chmod 666 /tmp/landscape_id.txt /tmp/portrait_id.txt

echo "Imported Media IDs: Landscape=$LANDSCAPE_ID, Portrait=$PORTRAIT_ID"

# ============================================================
# 4. Prepare Application UI
# ============================================================
echo "Checking Firefox status..."
if ! pgrep -x "firefox" > /dev/null 2>&1; then
    echo "Firefox not running, starting..."
    su - ga -c "DISPLAY=:1 firefox 'http://localhost/wp-admin/upload.php' > /tmp/firefox_restart.log 2>&1 &"
    sleep 10
fi

# Maximize and Focus
WID=$(DISPLAY=:1 wmctrl -l | grep -i "firefox\|mozilla\|wordpress" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
fi

take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="