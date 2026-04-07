#!/bin/bash
# Setup script for build_product_landing_page task
# Creates campaign assets and ensures WordPress is ready

echo "=== Setting up build_product_landing_page task ==="

source /workspace/scripts/task_utils.sh

# Record task start timestamp for anti-gaming
date +%s > /tmp/task_start_timestamp
chmod 666 /tmp/task_start_timestamp

# Record initial page and attachment counts
INITIAL_PAGE_COUNT=$(wp_cli post list --post_type=page --format=count 2>/dev/null || echo "0")
INITIAL_MEDIA_COUNT=$(wp_cli post list --post_type=attachment --format=count 2>/dev/null || echo "0")

echo "$INITIAL_PAGE_COUNT" | sudo tee /tmp/initial_page_count > /dev/null
echo "$INITIAL_MEDIA_COUNT" | sudo tee /tmp/initial_media_count > /dev/null
sudo chmod 666 /tmp/initial_page_count /tmp/initial_media_count

echo "Initial page count: $INITIAL_PAGE_COUNT"
echo "Initial media count: $INITIAL_MEDIA_COUNT"

# ============================================================
# Create Campaign Assets
# ============================================================
ASSETS_DIR="/home/ga/Campaign_Assets"
sudo -u ga mkdir -p "$ASSETS_DIR"

echo "Generating campaign assets in $ASSETS_DIR..."

# Create a realistic high-res background image using ImageMagick
sudo -u ga convert -size 1920x1080 gradient:navy-black -gravity center -pointsize 72 -fill white -annotate 0 'Urban Photography' "$ASSETS_DIR/hero-bg.jpg" 2>/dev/null || \
sudo -u ga convert -size 1920x1080 xc:black "$ASSETS_DIR/hero-bg.jpg" 2>/dev/null

# Create copy.txt
sudo -u ga cat > "$ASSETS_DIR/copy.txt" << 'EOF'
Intro:
Discover the hidden geometry of the city. This exclusive collection captures the raw essence of urban landscapes, offering a fresh perspective on the concrete jungle we inhabit.

Tier 1:
Digital Edition
High-resolution PDF featuring 200+ pages of stunning urban photography.

Tier 2:
Print Edition
Premium hardcover, 200 pages printed on archival-quality matte paper.

Tier 3:
Collector's Box
Signed hardcover edition + 3 exclusive 8x10 lithograph prints.
EOF

# Create video_link.txt
sudo -u ga cat > "$ASSETS_DIR/video_link.txt" << 'EOF'
https://www.youtube.com/watch?v=dQw4w9WgXcQ
EOF

# Set permissions
chmod -R 755 "$ASSETS_DIR"
chown -R ga:ga "$ASSETS_DIR"

# ============================================================
# Ensure Firefox is running
# ============================================================
echo "Checking Firefox status..."
if ! pgrep -x "firefox" > /dev/null 2>&1; then
    echo "Firefox not running, starting..."
    su - ga -c "DISPLAY=:1 firefox 'http://localhost/wp-admin/?autologin=admin' > /tmp/firefox_restart.log 2>&1 &"
    sleep 8
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
echo "Assets created in ~/Campaign_Assets."
echo "Agent must build the landing page using specific Gutenberg blocks."