#!/bin/bash
# Setup script for Inventory Scarcity Config task

echo "=== Setting up Inventory Scarcity Config Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Admin credentials
ADMIN_USER="admin"
ADMIN_PASS="Admin1234!"

# 1. Record initial configuration state (for anti-gaming verification)
echo "Recording initial configuration state..."

# Helper to get config value
get_config() {
    local path="$1"
    magento_query "SELECT value FROM core_config_data WHERE path='$path'" 2>/dev/null | tail -1
}

INIT_BACKORDERS=$(get_config "cataloginventory/item_options/backorders")
INIT_THRESHOLD=$(get_config "cataloginventory/options/stock_threshold_qty")
INIT_SHOW_OOS=$(get_config "cataloginventory/options/show_out_of_stock")
INIT_ALERTS=$(get_config "catalog/productalert/allow_stock")

# Store initial values in a JSON file
cat > /tmp/initial_config_state.json << EOF
{
    "backorders": "${INIT_BACKORDERS:-0}",
    "threshold": "${INIT_THRESHOLD:-0}",
    "show_out_of_stock": "${INIT_SHOW_OOS:-0}",
    "allow_alert": "${INIT_ALERTS:-0}"
}
EOF

echo "Initial state recorded:"
cat /tmp/initial_config_state.json

# 2. Ensure Firefox is running and focused on Magento admin
echo "Ensuring Firefox is running..."
MAGENTO_ADMIN_URL="http://localhost/admin"

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
echo "Focusing Firefox window..."
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 2
fi

# 3. Check login state and login if needed
WINDOW_TITLE=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "firefox\|mozilla" | head -1)
echo "Current window: $WINDOW_TITLE"

if echo "$WINDOW_TITLE" | grep -qi "admin" && ! echo "$WINDOW_TITLE" | grep -qi "dashboard"; then
    echo "Detected login page - attempting to log in..."
    sleep 2
    # Click to focus
    DISPLAY=:1 xdotool mousemove 960 540 click 1
    sleep 0.5
    # Fill credentials
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
    # Wait for dashboard
    sleep 10
fi

# 4. Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="
echo "Navigate to Stores > Configuration to begin."