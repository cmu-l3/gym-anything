#!/bin/bash
# Setup script for build_dynamic_landing_page task
echo "=== Setting up build_dynamic_landing_page task ==="

source /workspace/scripts/task_utils.sh

# Record task start timestamp
date +%s > /tmp/task_start_timestamp
chmod 666 /tmp/task_start_timestamp

# 1. Download real CC-0 image for the agent to upload
echo "Preparing local media files..."
mkdir -p /home/ga/Documents
# Using a public domain/CC-0 image from Wikimedia Commons
wget -qO /home/ga/Documents/hero_mountain.jpg "https://upload.wikimedia.org/wikipedia/commons/thumb/e/e7/Everest_North_Face_toward_Base_Camp_Tibet_Luca_Galuzzi_2006.jpg/1280px-Everest_North_Face_toward_Base_Camp_Tibet_Luca_Galuzzi_2006.jpg"
chown ga:ga /home/ga/Documents/hero_mountain.jpg

# 2. Ensure the "Travel" category exists and has posts
echo "Seeding taxonomy and posts..."
cd /var/www/html/wordpress
wp term create category "Travel" --description="Travel stories" --allow-root 2>/dev/null || true

# Get category ID
TRAVEL_ID=$(wp term list category --name="Travel" --field=term_id --allow-root | head -1)
echo "$TRAVEL_ID" | sudo tee /tmp/travel_category_id > /dev/null
chmod 666 /tmp/travel_category_id

# Assign the 3 most recent posts to the Travel category so the Query Loop has data to show
POST_IDS=$(wp post list --post_type=post --format=ids --allow-root | head -n 1 | tr ' ' '\n' | head -3)
for pid in $POST_IDS; do
    wp post term add "$pid" category "Travel" --allow-root 2>/dev/null || true
done

# 3. Ensure clean homepage state
wp option update show_on_front "posts" --allow-root 2>/dev/null || true
wp option update page_on_front "0" --allow-root 2>/dev/null || true

# 4. Ensure Firefox is running and focused on WP Admin
echo "Checking Firefox status..."
if ! pgrep -x "firefox" > /dev/null 2>&1; then
    su - ga -c "DISPLAY=:1 firefox 'http://localhost/wp-admin/' > /tmp/firefox_restart.log 2>&1 &"
    sleep 10
fi

WID=$(DISPLAY=:1 wmctrl -l | grep -i "firefox\|mozilla\|wordpress" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
fi

take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="