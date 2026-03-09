#!/bin/bash
# Setup script for Enable Product Reviews task
echo "=== Setting up Enable Product Reviews Task ==="

source /workspace/scripts/task_utils.sh

# 1. Ensure services are running
ensure_services_running 90

# 2. Record initial state
# Count existing comments to ensure we detect the new one
INITIAL_COMMENT_COUNT=$(drupal_db_query "SELECT COUNT(*) FROM comment_field_data")
echo "${INITIAL_COMMENT_COUNT:-0}" > /tmp/initial_comment_count

# Record timestamp for anti-gaming
date +%s > /tmp/task_start_timestamp

# 3. Clean slate check (optional but good practice)
# We want to ensure the comment type doesn't already exist from a previous run
# (Though the environment should be clean)
cd /var/www/html/drupal
if ./vendor/bin/drush config:get comment.type.product_review > /dev/null 2>&1; then
    echo "WARNING: comment.type.product_review already exists. Attempting to delete..."
    ./vendor/bin/drush config:delete comment.type.product_review -y
fi

# 4. Prepare the browser
# Navigate to the Structure page to give a helpful starting point
echo "Navigating Firefox to Structure page..."
if ensure_drupal_shown 60; then
    navigate_firefox_to "http://localhost/admin/structure"
else
    # Fallback if detection fails
    su - ga -c "DISPLAY=:1 firefox 'http://localhost/admin/structure' &"
fi

# 5. Maximize window
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# 6. Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="