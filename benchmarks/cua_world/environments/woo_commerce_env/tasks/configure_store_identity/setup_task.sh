#!/bin/bash
# Setup script for Configure Store Identity task

echo "=== Setting up Configure Store Identity Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# ==============================================================================
# 1. Clean up environment (Reset to known state)
# ==============================================================================
echo "Cleaning up existing 'Home' and 'News' pages..."
# Delete any pages named "Home" or "News" to force creation
wp post delete $(wp post list --post_type=page --name=home --field=ID --allow-root) --force --allow-root 2>/dev/null || true
wp post delete $(wp post list --post_type=page --name=news --field=ID --allow-root) --force --allow-root 2>/dev/null || true

# Reset settings to defaults
echo "Resetting General and Reading settings..."
wp option update blogname "WooCommerce Store" --allow-root 2>/dev/null
wp option update blogdescription "Just another WordPress site" --allow-root 2>/dev/null
wp option update timezone_string "UTC" --allow-root 2>/dev/null
wp option update show_on_front "posts" --allow-root 2>/dev/null
wp option update page_on_front "0" --allow-root 2>/dev/null
wp option update page_for_posts "0" --allow-root 2>/dev/null

# ==============================================================================
# 2. Record Initial State
# ==============================================================================
echo "Recording initial state..."
cat > /tmp/initial_state.json << EOF
{
    "blogname": "$(wp option get blogname --allow-root 2>/dev/null)",
    "blogdescription": "$(wp option get blogdescription --allow-root 2>/dev/null)",
    "timezone_string": "$(wp option get timezone_string --allow-root 2>/dev/null)",
    "show_on_front": "$(wp option get show_on_front --allow-root 2>/dev/null)",
    "timestamp": "$(date -Iseconds)"
}
EOF

# ==============================================================================
# 3. Prepare Firefox
# ==============================================================================
echo "Ensuring WordPress admin page is displayed..."
# Navigate specifically to the Dashboard to start
if ! pgrep -f firefox > /dev/null; then
    su - ga -c "DISPLAY=:1 firefox http://localhost/wp-admin/ &"
    sleep 10
else
    # If running, redirect to dashboard
    su - ga -c "DISPLAY=:1 firefox -new-tab http://localhost/wp-admin/"
    sleep 5
fi

# Ensure window is ready
if ! ensure_wordpress_shown 60; then
    echo "FATAL: Could not load WordPress admin page."
    exit 1
fi

# Focus and maximize
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="