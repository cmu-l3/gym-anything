#!/bin/bash
# Setup script for media_accessibility_cleanup task
echo "=== Setting up media_accessibility_cleanup task ==="

source /workspace/scripts/task_utils.sh

# Record timestamp for verification
date +%s > /tmp/task_start_time

echo "Configuring initial media settings..."
cd /var/www/html/wordpress
wp option update uploads_use_yearmonth_folders 1 --allow-root
wp option update thumbnail_size_w 150 --allow-root
wp option update thumbnail_size_h 150 --allow-root

# Create a valid 1x1 pixel transparent GIF for media uploads
echo "R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7" | base64 -d > /tmp/dummy.gif

import_media() {
    local title="$1"
    local existing=$(wp_db_query "SELECT ID FROM wp_posts WHERE post_title='$title' AND post_type='attachment' LIMIT 1")
    
    # If not found or if query failed
    if [ -z "$existing" ] || echo "$existing" | grep -qi "error"; then
        # Create a unique, safe filename
        local filename=$(echo "$title" | tr ' ' '_' | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9_').gif
        cp /tmp/dummy.gif "/tmp/$filename"
        
        cd /var/www/html/wordpress
        wp media import "/tmp/$filename" --title="$title" --allow-root > /dev/null 2>&1
        rm "/tmp/$filename"
        echo "Imported: $title"
    else
        echo "Already exists: $title (ID: $existing)"
        
        # Clear any existing alt text to ensure clean slate
        wp_db_query "DELETE FROM wp_postmeta WHERE post_id=$existing AND meta_key='_wp_attachment_image_alt'" > /dev/null 2>&1 || true
    fi
}

echo "Generating target media files in the library..."
import_media "Promo Banner Spring 2024"
import_media "Black Friday Sale Old"
import_media "Holiday Greetings 2023"
import_media "Headshot CEO Sarah"
import_media "Accessibility Diagram v2"
import_media "New York Office Lobby"
import_media "Quarterly Revenue Chart"

# Add a few extra noise images so the library isn't completely empty
import_media "Company Logo"
import_media "Team Photo 2024"

# Ensure Firefox is running
echo "Checking Firefox status..."
if ! pgrep -x "firefox" > /dev/null 2>&1; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox 'http://localhost/wp-admin/upload.php' > /tmp/firefox_restart.log 2>&1 &"
    sleep 8
fi

# Focus Firefox window
WID=$(DISPLAY=:1 wmctrl -l | grep -i "firefox\|mozilla\|wordpress" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="