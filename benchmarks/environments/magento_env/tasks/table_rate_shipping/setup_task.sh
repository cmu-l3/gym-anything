#!/bin/bash
# Setup script for Table Rate Shipping task

echo "=== Setting up Table Rate Shipping Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# =============================================================================
# 1. CLEAN STATE
# =============================================================================
echo "Clearing existing Table Rate configurations..."

# Disable Table Rates in all scopes
magento_query "DELETE FROM core_config_data WHERE path LIKE 'carriers/tablerate/%'" 2>/dev/null

# Clear the shipping rates table
magento_query "TRUNCATE TABLE shipping_tablerate" 2>/dev/null

echo "Database cleaned."

# =============================================================================
# 2. PREPARE BROWSER
# =============================================================================
# Admin credentials
ADMIN_USER="admin"
ADMIN_PASS="Admin1234!"
MAGENTO_ADMIN_URL="http://localhost/admin"

echo "Ensuring Firefox is running..."
if ! pgrep -f firefox > /dev/null; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox '$MAGENTO_ADMIN_URL' > /tmp/firefox_task.log 2>&1 &"
    sleep 8
fi

# Wait for Firefox window
if ! wait_for_window "firefox\|mozilla\|Magento" 30; then
    echo "WARNING: Firefox window not detected"
fi

# Focus Firefox window
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 2
fi

# Handle Login if needed
WINDOW_TITLE=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "firefox\|mozilla" | head -1)
if echo "$WINDOW_TITLE" | grep -qi "admin" && ! echo "$WINDOW_TITLE" | grep -qi "dashboard"; then
    echo "Detected login page - attempting to log in..."
    sleep 2
    DISPLAY=:1 xdotool mousemove 960 540 click 1
    sleep 0.5
    DISPLAY=:1 xdotool key Tab
    sleep 0.3
    DISPLAY=:1 xdotool key ctrl+a
    DISPLAY=:1 xdotool type --clearmodifiers "$ADMIN_USER"
    sleep 0.5
    DISPLAY=:1 xdotool key Tab
    sleep 0.3
    DISPLAY=:1 xdotool type --clearmodifiers "$ADMIN_PASS"
    sleep 0.5
    DISPLAY=:1 xdotool key Return
    sleep 10
fi

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Table Rate Shipping Task Setup Complete ==="
echo ""
echo "Task: Configure Table Rates for Main Website Scope"
echo "Rates to Import:"
echo "  - US, Weight 0+ : $15.00"
echo "  - US, Weight 10+ : $25.00"
echo "Scope: Main Website"
echo ""