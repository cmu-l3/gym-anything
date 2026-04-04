#!/bin/bash
# Setup script for Admin Security Setup task

echo "=== Setting up Admin Security Setup Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Record initial security configuration state
echo "Recording initial security configuration..."
PATHS=(
    "admin/security/password_lifetime"
    "admin/security/password_is_forced"
    "admin/security/lockout_failures"
    "admin/security/lockout_threshold"
    "admin/security/session_lifetime"
)

# Create a temporary JSON object for initial values
echo "{" > /tmp/initial_security_config.json
for path in "${PATHS[@]}"; do
    val=$(magento_query "SELECT value FROM core_config_data WHERE path='$path'" 2>/dev/null | tail -1 | tr -d '[:space:]')
    echo "  \"$path\": \"$val\"," >> /tmp/initial_security_config.json
done
# Close JSON (handling trailing comma hackily or just ignoring validity for now as we read line by line or fix it)
echo "  \"setup_complete\": true" >> /tmp/initial_security_config.json
echo "}" >> /tmp/initial_security_config.json

echo "Initial state recorded."

# Ensure Firefox is running and focused on Magento admin
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

# Check if we're on the login page (window title contains "login" or we need to log in)
WINDOW_TITLE=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "firefox\|mozilla" | head -1)
echo "Current window: $WINDOW_TITLE"

# Auto-login if needed
if echo "$WINDOW_TITLE" | grep -qi "admin" && ! echo "$WINDOW_TITLE" | grep -qi "dashboard"; then
    echo "Detected login page - attempting to log in..."
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

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Admin Security Setup Task Setup Complete ==="
echo ""
echo "Navigate to: Stores > Configuration > Advanced > Admin"
echo "Magento Admin: http://localhost/admin  |  admin / Admin1234!"
echo ""