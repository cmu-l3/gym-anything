#!/bin/bash
# Setup script for setup_digital_archives task (pre_task hook)

echo "=== Setting up setup_digital_archives task ==="

source /workspace/scripts/task_utils.sh

# Remove any existing pages with the target names to ensure a clean start
cd /var/www/html/wordpress
TARGET_PAGES=("Digital Archives" "Public Collections" "Restricted Manuscripts" "Oral History Recordings" "Photographic Archives" "Research Access Policy")

for title in "${TARGET_PAGES[@]}"; do
    PAGE_IDS=$(wp post list --post_type=page --post_status=any --title="$title" --format=ids --allow-root 2>/dev/null)
    if [ -n "$PAGE_IDS" ]; then
        echo "Removing existing conflicting page: $title (IDs: $PAGE_IDS)"
        wp post delete $PAGE_IDS --force --allow-root 2>/dev/null || true
    fi
done

# Record baseline counts and timestamp for anti-gaming
date +%s | sudo tee /tmp/task_start_timestamp > /dev/null
sudo chmod 666 /tmp/task_start_timestamp

INITIAL_PAGE_COUNT=$(wp post list --post_type=page --format=count --allow-root 2>/dev/null || echo "0")
echo "$INITIAL_PAGE_COUNT" | sudo tee /tmp/initial_page_count > /dev/null
sudo chmod 666 /tmp/initial_page_count
echo "Initial page count: $INITIAL_PAGE_COUNT"

# Ensure Firefox is running and focused on the WordPress Pages list
echo "Checking Firefox status..."
if ! pgrep -x "firefox" > /dev/null 2>&1; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox 'http://localhost/wp-admin/edit.php?post_type=page' > /tmp/firefox_restart.log 2>&1 &"
    sleep 10
else
    # Navigate to pages list
    su - ga -c "DISPLAY=:1 firefox 'http://localhost/wp-admin/edit.php?post_type=page' &"
    sleep 5
fi

# Maximize and focus Firefox
WID=$(DISPLAY=:1 wmctrl -l | grep -i "firefox\|mozilla\|wordpress" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
    echo "Firefox window focused: $WID"
fi

# Take initial screenshot for evidence
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="