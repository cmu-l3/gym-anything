#!/bin/bash
# Setup script for execute_db_search_replace_migration
# Injects staging URLs and a serialized canary option to test for safe search-replace

echo "=== Setting up Database Search and Replace Task ==="

source /workspace/scripts/task_utils.sh

# Record task start timestamp for anti-gaming checks
date +%s > /tmp/task_start_timestamp
chmod 666 /tmp/task_start_timestamp

# 1. Inject the Canary Serialized Option
# This perfectly serialized array will break if a raw SQL string replace changes
# "http://staging.local" (20 chars) to "http://localhost" (16 chars) without updating the length.
echo "Injecting serialized canary into wp_options..."
CANARY_VAL='a:2:{s:7:"siteurl";s:20:"http://staging.local";s:9:"image_url";s:32:"http://staging.local/image.jpg";}'
wp_db_query "INSERT INTO wp_options (option_name, option_value, autoload) VALUES ('migration_canary_widget', '$CANARY_VAL', 'yes') ON DUPLICATE KEY UPDATE option_value='$CANARY_VAL'"

# 2. Break Core URLs
echo "Updating siteurl and home options to staging URL..."
wp_db_query "UPDATE wp_options SET option_value='http://staging.local' WHERE option_name IN ('siteurl', 'home')"

# 3. Inject staging URLs into posts and meta
echo "Injecting staging URLs into posts and postmeta..."
wp_db_query "UPDATE wp_posts SET post_content = REPLACE(post_content, 'http://localhost', 'http://staging.local')"
wp_db_query "UPDATE wp_postmeta SET meta_value = REPLACE(meta_value, 'http://localhost', 'http://staging.local')"

# Flush cache just in case
cd /var/www/html/wordpress
wp cache flush --allow-root 2>/dev/null || true

# 4. Launch terminal for the agent
if ! pgrep -x "gnome-terminal" > /dev/null 2>&1; then
    echo "Starting terminal..."
    su - ga -c "DISPLAY=:1 gnome-terminal --working-directory=/var/www/html/wordpress &"
    sleep 3
fi

# 5. Launch Firefox to demonstrate the broken site
echo "Starting Firefox..."
if ! pgrep -x "firefox" > /dev/null 2>&1; then
    su - ga -c "DISPLAY=:1 firefox 'http://localhost/' > /tmp/firefox_task.log 2>&1 &"
    sleep 5
fi

# Focus and maximize Firefox
WID=$(DISPLAY=:1 wmctrl -l | grep -i "firefox\|mozilla" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Take initial screenshot showing the broken state (likely a connection error or redirect loop)
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="
echo "The site is now broken and redirecting to http://staging.local."
echo "Agent must perform a safe database search & replace."