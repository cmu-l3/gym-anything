#!/bin/bash
# Setup script for create_research_guide task (pre_task hook)

echo "=== Setting up create_research_guide task ==="

# Source utility functions
source /workspace/scripts/task_utils.sh

# Record task start timestamp for anti-gaming
date +%s > /tmp/task_start_timestamp
chmod 666 /tmp/task_start_timestamp

# Clean up any existing pages with these titles to ensure a clean slate
echo "Cleaning up any pre-existing guide pages..."
for title in "Digital Humanities Research Guide" "Getting Started with Digital Humanities" "Primary Source Databases" "Digital Tools and Software" "Citation and Attribution Guide"; do
    wp_cli post list --post_type=page --post_status=any --title="$title" --field=ID --allow-root 2>/dev/null | while read -r pid; do
        if [ -n "$pid" ]; then
            echo "Deleting existing page '$title' (ID: $pid)"
            wp_cli post delete "$pid" --force --allow-root 2>/dev/null || true
        fi
    done
done

# Record initial page count
INITIAL_PAGE_COUNT=$(wp_cli post list --post_type=page --post_status=publish --format=count --allow-root 2>/dev/null || echo "0")
echo "$INITIAL_PAGE_COUNT" | sudo tee /tmp/initial_page_count > /dev/null
sudo chmod 666 /tmp/initial_page_count
echo "Initial published page count: $INITIAL_PAGE_COUNT"

# Ensure Firefox is running and focused on WordPress admin
echo "Checking Firefox status..."
if ! pgrep -x "firefox" > /dev/null 2>&1; then
    echo "Firefox not running, starting..."
    su - ga -c "DISPLAY=:1 firefox 'http://localhost/wp-admin/edit.php?post_type=page' > /tmp/firefox_restart.log 2>&1 &"
    sleep 10
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
echo "Agent should now create 1 parent page and 4 child pages for the Research Guide."