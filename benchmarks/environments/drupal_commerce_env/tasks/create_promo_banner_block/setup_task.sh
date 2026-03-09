#!/bin/bash
# Setup script for create_promo_banner_block task
echo "=== Setting up create_promo_banner_block ==="

source /workspace/scripts/task_utils.sh

# Ensure services are running
ensure_services_running 120

# Record initial state
# Count existing custom blocks
INITIAL_BLOCK_COUNT=$(drupal_db_query "SELECT COUNT(*) FROM block_content_field_data" 2>/dev/null || echo "0")
echo "$INITIAL_BLOCK_COUNT" > /tmp/initial_block_count

# Record max ID to detect new ones
MAX_BLOCK_ID=$(drupal_db_query "SELECT MAX(id) FROM block_content_field_data" 2>/dev/null || echo "0")
if [ "$MAX_BLOCK_ID" == "NULL" ]; then MAX_BLOCK_ID=0; fi
echo "$MAX_BLOCK_ID" > /tmp/max_block_id

# Timestamp for anti-gaming
date +%s > /tmp/task_start_time

# Ensure Drupal admin is ready
ensure_drupal_shown 60

# Navigate to Block Layout page as a helpful starting point
# (or Structure page)
echo "Navigating to Structure..."
navigate_firefox_to "http://localhost/admin/structure"
sleep 5

# Focus and maximize
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="