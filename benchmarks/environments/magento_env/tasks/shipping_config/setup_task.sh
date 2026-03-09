#!/bin/bash
# Setup script for Shipping Configuration task

echo "=== Setting up Shipping Configuration Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Admin credentials
ADMIN_USER="admin"
ADMIN_PASS="Admin1234!"
MAGENTO_ADMIN_URL="http://localhost/admin"

# Record task start time
date +%s > /tmp/task_start_time.txt

# Helper to get a config value
get_config() {
    local path="$1"
    magento_query "SELECT value FROM core_config_data WHERE path='$path' AND scope='default' AND scope_id=0" 2>/dev/null | tail -1
}

# Record initial configuration state (to detect "do nothing" or changes)
# We store this to compare later if needed, though verification mostly checks final state matches target
echo "Recording initial config state..."
cat > /tmp/initial_config_state.json << EOF
{
    "origin_country": "$(get_config 'shipping/origin/country_id')",
    "origin_region": "$(get_config 'shipping/origin/region_id')",
    "origin_postcode": "$(get_config 'shipping/origin/postcode')",
    "flatrate_active": "$(get_config 'carriers/flatrate/active')",
    "flatrate_price": "$(get_config 'carriers/flatrate/price')",
    "freeshipping_active": "$(get_config 'carriers/freeshipping/active')"
}
EOF

# Ensure Firefox is running
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
echo "Focusing Firefox window..."
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 2
fi

# Check if we're on the login page and log in if needed
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

echo "=== Shipping Config Task Setup Complete ==="