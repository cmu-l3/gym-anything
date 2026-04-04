#!/bin/bash
# Setup script for Configure Shop Sidebar task

echo "=== Setting up Configure Shop Sidebar Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Verify database connectivity
if ! check_db_connection; then
    echo "ERROR: Database not reachable. Cannot set up task."
    exit 1
fi

# ==============================================================================
# 1. Reset Sidebar to a "Messy" Initial State
# ==============================================================================
echo "Resetting sidebar widgets to initial messy state..."

# Clear existing widgets from the primary sidebar (sidebar-1 in Storefront theme)
wp widget reset sidebar-1 --allow-root 2>/dev/null

# Add a mix of default WordPress widgets to require cleanup
# We intentionally DO NOT include the target WooCommerce widgets here (or include them wrongly)
# to force the agent to take action.
wp widget add search sidebar-1 --title="Search Site" --allow-root 2>/dev/null
wp widget add recent-posts sidebar-1 --title="Latest News" --allow-root 2>/dev/null
wp widget add archives sidebar-1 --title="Archives" --allow-root 2>/dev/null
wp widget add categories sidebar-1 --title="Blog Categories" --allow-root 2>/dev/null
wp widget add meta sidebar-1 --title="Meta" --allow-root 2>/dev/null

# Record initial state for anti-gaming comparison
echo "Recording initial sidebar state..."
wp option get sidebars_widgets --format=json --allow-root > /tmp/initial_sidebars_widgets.json

# ==============================================================================
# 2. Prepare Environment
# ==============================================================================

# Ensure WordPress admin page is displayed
echo "Ensuring WordPress admin page is displayed..."
if ! ensure_wordpress_shown 60; then
    echo "FATAL: Could not load WordPress admin page - task cannot proceed"
    exit 1
fi

# Focus and maximize Firefox window
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
fi

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="