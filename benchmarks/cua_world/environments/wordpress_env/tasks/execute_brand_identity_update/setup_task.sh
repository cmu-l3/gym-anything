#!/bin/bash
# Setup script for execute_brand_identity_update
echo "=== Setting up Brand Identity Update Task ==="

source /workspace/scripts/task_utils.sh

# Record task start timestamp
date +%s > /tmp/task_start_time.txt
chmod 666 /tmp/task_start_time.txt

# Create asset directory
mkdir -p /home/ga/Brand_Assets

# Download real brand assets from Wikimedia Commons (or fallback to generated text placeholders)
echo "Downloading real brand assets..."
wget -qO /home/ga/Brand_Assets/wikimedia_logo.png "https://upload.wikimedia.org/wikipedia/commons/thumb/1/1a/Wikimedia_Foundation_logo_-_horizontal.svg/800px-Wikimedia_Foundation_logo_-_horizontal.svg.png" || \
    convert -size 800x200 xc:transparent -fill black -gravity center -draw "text 0,0 'Wikimedia Foundation'" /home/ga/Brand_Assets/wikimedia_logo.png

wget -qO /home/ga/Brand_Assets/wikimedia_icon.png "https://upload.wikimedia.org/wikipedia/commons/thumb/8/8b/Wikimedia-logo_black.svg/512px-Wikimedia-logo_black.svg.png" || \
    convert -size 512x512 xc:white -fill black -gravity center -draw "text 0,0 'W'" /home/ga/Brand_Assets/wikimedia_icon.png

chown -R ga:ga /home/ga/Brand_Assets
chmod -R 644 /home/ga/Brand_Assets/*

# Ensure WordPress defaults are standard (so we aren't starting with partial success)
cd /var/www/html/wordpress
wp option update blogname "My WordPress Blog" --allow-root 2>/dev/null
wp option update blogdescription "A WordPress blog for testing and demonstrations" --allow-root 2>/dev/null
wp option update admin_email "admin@example.com" --allow-root 2>/dev/null
wp option delete new_admin_email --allow-root 2>/dev/null

# Remove any existing custom logos or icons
wp theme mod remove custom_logo --allow-root 2>/dev/null
wp option delete site_icon --allow-root 2>/dev/null

# Clean up any previously created 'Press Resources' pages
wp post delete $(wp post list --post_type=page --name="press-resources" --format=ids --allow-root) --force --allow-root 2>/dev/null || true

# Check if Firefox is running
echo "Checking Firefox status..."
if ! pgrep -x "firefox" > /dev/null 2>&1; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox 'http://localhost/wp-admin/' > /tmp/firefox_restart.log 2>&1 &"
    sleep 8
fi

# Focus Firefox window and maximize
WID=$(DISPLAY=:1 wmctrl -l | grep -i "firefox\|mozilla\|wordpress" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
fi

# Take initial screenshot showing clean starting state
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="