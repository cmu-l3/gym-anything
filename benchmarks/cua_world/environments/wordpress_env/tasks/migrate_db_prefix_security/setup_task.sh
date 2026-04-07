#!/bin/bash
# Setup script for migrate_db_prefix_security task
# Ensures WordPress is running on the default wp_ prefix and records baseline

echo "=== Setting up migrate_db_prefix_security task ==="

source /workspace/scripts/task_utils.sh

# Record task start timestamp
date +%s > /tmp/task_start_timestamp
chmod 666 /tmp/task_start_timestamp

# Verify initial database state (should be using wp_ prefix)
echo "Checking initial database state..."
INITIAL_WP_TABLES=$(wp_db_query "SHOW TABLES LIKE 'wp_%'" | wc -l)
echo "Found $INITIAL_WP_TABLES tables with 'wp_' prefix."

if [ "$INITIAL_WP_TABLES" -eq 0 ]; then
    echo "ERROR: WordPress doesn't appear to be using the expected 'wp_' prefix initially."
fi

# Ensure Firefox is running and focused on WordPress admin
echo "Checking Firefox status..."
if ! pgrep -x "firefox" > /dev/null 2>&1; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox 'http://localhost/wp-admin/' > /tmp/firefox_restart.log 2>&1 &"
    sleep 10
fi

# Focus Firefox window
echo "Focusing Firefox window..."
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
echo "Agent must migrate the WordPress database prefix from 'wp_' to 'sec24_'."