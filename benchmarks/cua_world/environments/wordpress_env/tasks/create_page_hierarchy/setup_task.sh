#!/bin/bash
# Setup script for create_page_hierarchy task (pre_task hook)

echo "=== Setting up create_page_hierarchy task ==="

# Source utility functions
source /workspace/scripts/task_utils.sh

# Record task start timestamp for anti-gaming verification
date +%s | sudo tee /tmp/task_start_timestamp > /dev/null
sudo chmod 666 /tmp/task_start_timestamp

# Clean up any previously created pages with these names to ensure a clean slate
echo "Cleaning up any existing pages with target titles..."
cd /var/www/html/wordpress

TITLES=(
    "About the Department" "Academic Programs" "Research & Scholarship" 
    "Mission Statement" "Faculty Directory" "Contact Information" 
    "Undergraduate Studies" "Graduate Studies" "Course Catalog" 
    "Current Projects" "Publications" "Funding Opportunities"
)

for title in "${TITLES[@]}"; do
    PAGE_IDS=$(wp post list --post_type=page --title="$title" --field=ID --allow-root 2>/dev/null)
    if [ -n "$PAGE_IDS" ]; then
        for id in $PAGE_IDS; do
            echo "Deleting existing page: $title (ID: $id)"
            wp post delete "$id" --force --allow-root 2>/dev/null || true
        done
    fi
done

# Record initial page count
INITIAL_PAGE_COUNT=$(wp post list --post_type=page --post_status=publish --format=count --allow-root 2>/dev/null || echo "0")
echo "$INITIAL_PAGE_COUNT" | sudo tee /tmp/initial_page_count > /dev/null
sudo chmod 666 /tmp/initial_page_count
echo "Initial published page count: $INITIAL_PAGE_COUNT"

# Ensure Firefox is running and focused on WordPress admin
echo "Checking Firefox status..."

# Check if Firefox is running
if ! pgrep -x "firefox" > /dev/null 2>&1; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox 'http://localhost/wp-admin/edit.php?post_type=page' > /tmp/firefox_restart.log 2>&1 &"
    sleep 8
else
    # Navigate to Pages list
    su - ga -c "DISPLAY=:1 firefox 'http://localhost/wp-admin/edit.php?post_type=page' > /dev/null 2>&1 &"
    sleep 3
fi

# Focus and maximize Firefox window
echo "Focusing Firefox window..."
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