#!/bin/bash
# Setup script for configure_content_access task
echo "=== Setting up configure_content_access task ==="

source /workspace/scripts/task_utils.sh
cd /var/www/html/wordpress

# Ensure the required posts exist (create them if missing or deleted by earlier tasks)
echo "Verifying baseline posts exist..."
if ! wp post list --post_type=post --title="Getting Started with WordPress" --field=ID --allow-root | grep -q "[0-9]"; then
    wp post create --post_type=post --post_status=publish --post_title="Getting Started with WordPress" \
        --post_content="Welcome to WordPress! This is your first step into the world of content management systems." \
        --allow-root
fi

if ! wp post list --post_type=post --title="10 Essential WordPress Plugins" --field=ID --allow-root | grep -q "[0-9]"; then
    wp post create --post_type=post --post_status=publish --post_title="10 Essential WordPress Plugins Every Site Needs" \
        --post_content="Building a successful WordPress site requires the right tools." \
        --allow-root
fi

# Ensure both posts start in a published state
wp post list --post_type=post --post_status=any --search="Getting Started with WordPress" --field=ID --allow-root | xargs -I {} wp post update {} --post_status=publish --allow-root
wp post list --post_type=post --post_status=any --search="10 Essential WordPress Plugins" --field=ID --allow-root | xargs -I {} wp post update {} --post_status=publish --allow-root

# Clean up any existing pages that might conflict from previous attempts
wp post list --post_type=page --search="Staff Resources Portal" --field=ID --allow-root | xargs -r wp post delete --force --allow-root
wp post list --post_type=page --search="Collection Development Policy" --field=ID --allow-root | xargs -r wp post delete --force --allow-root
wp post list --post_type=page --search="Accessing Restricted Resources" --field=ID --allow-root | xargs -r wp post delete --force --allow-root

# Record MAX post ID to verify that new pages are newly created
INITIAL_MAX_ID=$(wp db query "SELECT MAX(ID) FROM wp_posts" --skip-column-names --allow-root)
echo "$INITIAL_MAX_ID" > /tmp/task_initial_max_id.txt
chmod 666 /tmp/task_initial_max_id.txt

# Record task start time
date +%s > /tmp/task_start_time.txt
chmod 666 /tmp/task_start_time.txt

# Start Firefox and navigate to WordPress Admin
echo "Starting Firefox..."
if ! pgrep -x "firefox" > /dev/null 2>&1; then
    su - ga -c "DISPLAY=:1 firefox 'http://localhost/wp-admin/' > /tmp/firefox.log 2>&1 &"
    sleep 8
fi

# Maximize and Focus
WID=$(DISPLAY=:1 wmctrl -l | grep -i "firefox\|mozilla\|wordpress" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Allow UI to settle
sleep 2

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="