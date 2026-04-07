#!/bin/bash
# Setup script for cleanup_legacy_shortcodes task
echo "=== Setting up cleanup_legacy_shortcodes task ==="

source /workspace/scripts/task_utils.sh

cd /var/www/html/wordpress

# Create Post 1 (Quote target)
P1_ID=$(wp post create --post_type=post --post_status=publish --post_title="Service Interruption Notice" \
    --post_content='<!-- wp:paragraph --><p>Please read the following important announcement:</p><!-- /wp:paragraph -->

[legacy_alert]Our servers will be down for maintenance on Sunday.[/legacy_alert]

<!-- wp:paragraph --><p>We apologize for any inconvenience this may cause.</p><!-- /wp:paragraph -->' \
    --porcelain --allow-root)

# Create Post 2 (Video target)
P2_ID=$(wp post create --post_type=post --post_status=publish --post_title="Watch our latest webinar" \
    --post_content='<!-- wp:paragraph --><p>Catch up on our latest quarterly insights below.</p><!-- /wp:paragraph -->

[legacy_video id="jNQXAC9IVRw"]

<!-- wp:paragraph --><p>Let us know your thoughts in the comments!</p><!-- /wp:paragraph -->' \
    --porcelain --allow-root)

# Create Post 3 (Button target)
P3_ID=$(wp post create --post_type=post --post_status=publish --post_title="Annual Report 2025" \
    --post_content='<!-- wp:paragraph --><p>Our yearly metrics are finally compiled and ready for review.</p><!-- /wp:paragraph -->

[legacy_button url="/annual-report-pdf" label="Download Report"]' \
    --porcelain --allow-root)

echo "Created target posts: $P1_ID, $P2_ID, $P3_ID"

# Record task start timestamp (to verify posts are updated during the task)
sleep 2
date +%s > /tmp/task_start_timestamp
chmod 666 /tmp/task_start_timestamp
echo "Task baseline timestamp saved."

# Ensure Firefox is running and focused on the Posts list
echo "Checking Firefox status..."
if ! pgrep -x "firefox" > /dev/null 2>&1; then
    su - ga -c "DISPLAY=:1 firefox 'http://localhost/wp-admin/edit.php' > /tmp/firefox_task.log 2>&1 &"
    sleep 8
else
    # Navigate existing firefox to the Posts list
    su - ga -c "DISPLAY=:1 firefox -new-tab 'http://localhost/wp-admin/edit.php' > /dev/null 2>&1 &"
    sleep 3
fi

# Maximize and Focus Firefox
WID=$(DISPLAY=:1 wmctrl -l | grep -i "firefox\|mozilla\|wordpress" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
    echo "Firefox window focused: $WID"
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="