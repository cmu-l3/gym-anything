#!/bin/bash
# Setup script for implement_faq_schema_and_rich_snippets task

echo "=== Setting up FAQ Schema task ==="

source /workspace/scripts/task_utils.sh

# Record task start timestamp for anti-gaming verification
date +%s | sudo tee /tmp/task_start_time > /dev/null
sudo chmod 666 /tmp/task_start_time

# Find the target post ID
POST_TITLE="Getting Started with WordPress"
TARGET_POST_ID=$(wp_db_query "SELECT ID FROM wp_posts WHERE post_title='$POST_TITLE' AND post_type='post' AND post_status='publish' ORDER BY ID DESC LIMIT 1")

if [ -n "$TARGET_POST_ID" ]; then
    echo "Found target post: '$POST_TITLE' (ID: $TARGET_POST_ID)"
    echo "$TARGET_POST_ID" | sudo tee /tmp/target_post_id > /dev/null
    sudo chmod 666 /tmp/target_post_id
    
    # Save initial modification time to detect if agent actually saved the post
    INITIAL_MODIFIED=$(wp_db_query "SELECT post_modified FROM wp_posts WHERE ID=$TARGET_POST_ID")
    echo "$INITIAL_MODIFIED" | sudo tee /tmp/initial_post_modified > /dev/null
    sudo chmod 666 /tmp/initial_post_modified
else
    echo "ERROR: Target post not found! Verification will fail."
    # The post is created by the environment setup, so it should exist.
fi

# Make sure Firefox is running and focused on the WordPress admin
echo "Checking Firefox status..."
if ! pgrep -x "firefox" > /dev/null 2>&1; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox 'http://localhost/wp-admin/edit.php' > /tmp/firefox.log 2>&1 &"
    sleep 8
fi

# Focus and maximize Firefox window
WID=$(DISPLAY=:1 wmctrl -l | grep -i "firefox\|mozilla\|wordpress" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
    echo "Firefox window focused."
fi

# Take initial screenshot as baseline evidence
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="