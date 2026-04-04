#!/bin/bash
# Setup script for Multi-Source Inventory task

echo "=== Setting up MSI Task ==="

source /workspace/scripts/task_utils.sh

# 1. Record initial state of inventory tables
echo "Recording initial inventory counts..."
INITIAL_SOURCE_COUNT=$(magento_query "SELECT COUNT(*) FROM inventory_source" 2>/dev/null | tail -1 | tr -d '[:space:]' || echo "0")
INITIAL_STOCK_COUNT=$(magento_query "SELECT COUNT(*) FROM inventory_stock" 2>/dev/null | tail -1 | tr -d '[:space:]' || echo "0")

echo "$INITIAL_SOURCE_COUNT" > /tmp/initial_source_count
echo "$INITIAL_STOCK_COUNT" > /tmp/initial_stock_count

# 2. Ensure Magento Admin is accessible
echo "Ensuring Firefox is running..."
MAGENTO_ADMIN_URL="http://localhost/admin"

if ! pgrep -f firefox > /dev/null; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox '$MAGENTO_ADMIN_URL' > /tmp/firefox_task.log 2>&1 &"
    sleep 10
fi

# 3. Wait for window and focus
if ! wait_for_window "firefox\|mozilla\|Magento" 30; then
    echo "WARNING: Firefox window not detected"
fi

WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 2
fi

# 4. Handle Login if needed
WINDOW_TITLE=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "firefox\|mozilla" | head -1)
if echo "$WINDOW_TITLE" | grep -qi "admin" && ! echo "$WINDOW_TITLE" | grep -qi "dashboard"; then
    echo "Attempting login..."
    sleep 2
    DISPLAY=:1 xdotool mousemove 960 540 click 1
    sleep 0.5
    DISPLAY=:1 xdotool key Tab
    sleep 0.3
    DISPLAY=:1 xdotool key ctrl+a
    DISPLAY=:1 xdotool type --clearmodifiers "admin"
    sleep 0.5
    DISPLAY=:1 xdotool key Tab
    sleep 0.3
    DISPLAY=:1 xdotool type --clearmodifiers "Admin1234!"
    sleep 0.5
    DISPLAY=:1 xdotool key Return
    sleep 10
fi

# 5. Capture initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== MSI Task Setup Complete ==="
echo "Navigate to: Stores > Inventory > Sources / Stocks"