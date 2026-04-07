#!/bin/bash
# Setup script for create_navigation_menu task (pre_task hook)

echo "=== Setting up create_navigation_menu task ==="

# Source utility functions
source /workspace/scripts/task_utils.sh

# Record task start timestamp
date +%s > /tmp/task_start_timestamp
chmod 666 /tmp/task_start_timestamp

cd /var/www/html/wordpress

# 1. Install and activate Twenty Twenty-One theme (supports classical menus)
echo "Installing Twenty Twenty-One theme..."
wp theme install twentytwentyone --activate --allow-root 2>&1

# 2. Delete any existing menus to ensure a clean state
echo "Cleaning up existing menus..."
MENU_IDS=$(wp menu list --field=term_id --allow-root 2>/dev/null || echo "")
for ID in $MENU_IDS; do
    wp menu delete "$ID" --allow-root 2>/dev/null
done

# 3. Create required pages if they don't exist
echo "Setting up required pages..."
PAGES=("About Us" "Cakes" "Pastries" "Blog" "Contact")

for PAGE_TITLE in "${PAGES[@]}"; do
    # Check if page exists
    EXISTS=$(wp_db_query "SELECT ID FROM wp_posts WHERE post_title='$PAGE_TITLE' AND post_type='page' AND post_status='publish' LIMIT 1")
    if [ -z "$EXISTS" ]; then
        echo "Creating page: $PAGE_TITLE"
        wp post create --post_type=page --post_status=publish --post_title="$PAGE_TITLE" --post_content="Welcome to the $PAGE_TITLE page." --allow-root >/dev/null
    else
        echo "Page exists: $PAGE_TITLE (ID: $EXISTS)"
    fi
done

# 4. Ensure Firefox is running and focused on WordPress admin
echo "Checking Firefox status..."
if ! pgrep -x "firefox" > /dev/null 2>&1; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox 'http://localhost/wp-admin/nav-menus.php' > /tmp/firefox_restart.log 2>&1 &"
    sleep 8
fi

# Focus Firefox window and maximize
WID=$(DISPLAY=:1 wmctrl -l | grep -i "firefox\|mozilla\|wordpress" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
    echo "Firefox window focused"
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="