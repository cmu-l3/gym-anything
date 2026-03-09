#!/bin/bash
# Setup script for Onboard Shop Manager task

echo "=== Setting up Onboard Shop Manager Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure clean state: Remove the target user if they already exist
echo "Ensuring target user does not exist..."
if wp user get morgan_ops --field=ID --allow-root > /dev/null 2>&1; then
    echo "User morgan_ops found, deleting..."
    wp user delete morgan_ops --yes --allow-root
fi

# Record initial user count
INITIAL_COUNT=$(wc_query "SELECT COUNT(*) FROM wp_users")
echo "$INITIAL_COUNT" > /tmp/initial_user_count
echo "Initial user count: $INITIAL_COUNT"

# CRITICAL: Ensure WordPress admin page is showing
echo "Ensuring WordPress admin page is displayed..."
if ! ensure_wordpress_shown 60; then
    echo "FATAL: Could not load WordPress admin page - task cannot proceed"
    exit 1
fi

# Navigate to Dashboard or Users page to start
# We'll start at Dashboard to make them navigate
su - ga -c "DISPLAY=:1 firefox http://localhost/wp-admin/index.php &"
sleep 5

# Focus and maximize Firefox window
echo "Focusing Firefox window..."
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
fi

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png
echo "Initial screenshot saved"

echo "=== Onboard Shop Manager Setup Complete ==="