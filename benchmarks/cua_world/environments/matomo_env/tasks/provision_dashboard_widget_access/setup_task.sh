#!/bin/bash
# Setup script for Provision Dashboard Widget Access task

echo "=== Setting up Provision Dashboard Widget Access Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_timestamp

# Ensure Matomo is ready
if ! matomo_is_installed; then
    echo "Waiting for Matomo to be ready..."
    sleep 10
fi

# Clean up previous attempts (if any)
echo "Cleaning up previous 'lobby_display' user..."
matomo_query "DELETE FROM matomo_access WHERE login='lobby_display'" 2>/dev/null || true
matomo_query "DELETE FROM matomo_user WHERE login='lobby_display'" 2>/dev/null || true
# Note: Tokens in separate table are linked by login, but usually cascade delete isn't automatic in simple scripts
# We'll rely on user deletion to invalidate tokens effectively for the verification logic

# Remove output file
rm -f /home/ga/lobby_widget.html 2>/dev/null || true

# Ensure 'Initial Site' exists (ID 1)
SITE_COUNT=$(matomo_query "SELECT COUNT(*) FROM matomo_site WHERE idsite=1" 2>/dev/null || echo "0")
if [ "$SITE_COUNT" = "0" ]; then
    echo "Creating Initial Site..."
    matomo_query "INSERT INTO matomo_site (idsite, name, main_url, ts_created, ecommerce, timezone, currency, type) VALUES (1, 'Initial Site', 'https://example.com', NOW(), 0, 'UTC', 'USD', 'website')" 2>/dev/null
fi

# Ensure Firefox is running
pkill -f firefox 2>/dev/null || true
su - ga -c "DISPLAY=:1 firefox 'http://localhost/' > /tmp/firefox_task.log 2>&1 &"
sleep 5

# Maximize window
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Take initial screenshot
take_screenshot /tmp/task_initial_screenshot.png

echo "=== Setup Complete ==="