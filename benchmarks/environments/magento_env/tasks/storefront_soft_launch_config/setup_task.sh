#!/bin/bash
# Setup script for Soft Launch Configuration task

echo "=== Setting up Soft Launch Configuration Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Admin credentials
ADMIN_USER="admin"
ADMIN_PASS="Admin1234!"

# 1. Clean up any previous state to ensure a fair test
echo "Cleaning up previous task artifacts..."
# Delete the CMS page if it exists
magento_query "DELETE FROM cms_page WHERE identifier='coming-soon'" 2>/dev/null || true
# Reset Homepage to default ('home')
magento_query "DELETE FROM core_config_data WHERE path='web/default/cms_home_page'" 2>/dev/null || true
magento_query "INSERT INTO core_config_data (scope, scope_id, path, value) VALUES ('default', 0, 'web/default/cms_home_page', 'home') ON DUPLICATE KEY UPDATE value='home'" 2>/dev/null || true
# Reset Demo Notice to disabled (0)
magento_query "DELETE FROM core_config_data WHERE path='design/head/demonotice'" 2>/dev/null || true
magento_query "INSERT INTO core_config_data (scope, scope_id, path, value) VALUES ('default', 0, 'design/head/demonotice', '0') ON DUPLICATE KEY UPDATE value='0'" 2>/dev/null || true

# Clear cache to apply DB changes
docker exec magento-web php bin/magento cache:clean config full_page >/dev/null 2>&1 || true

# 2. Record Initial State
echo "Recording initial state..."
INITIAL_HOMEPAGE=$(magento_query "SELECT value FROM core_config_data WHERE path='web/default/cms_home_page' LIMIT 1" 2>/dev/null)
INITIAL_DEMONOTICE=$(magento_query "SELECT value FROM core_config_data WHERE path='design/head/demonotice' LIMIT 1" 2>/dev/null)

echo "$INITIAL_HOMEPAGE" > /tmp/initial_homepage_config
echo "$INITIAL_DEMONOTICE" > /tmp/initial_demonotice_config

# 3. Ensure Firefox is running and focused on Magento admin
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

# If we detect we're on the login page (title contains "Admin" but not "Dashboard"), try to log in
if echo "$WINDOW_TITLE" | grep -qi "admin" && ! echo "$WINDOW_TITLE" | grep -qi "dashboard"; then
    echo "Detected login page - attempting to log in..."
    sleep 2

    # Click in the window to focus
    DISPLAY=:1 xdotool mousemove 960 540 click 1
    sleep 0.5

    # Tab to first field and type username
    DISPLAY=:1 xdotool key Tab
    sleep 0.3
    DISPLAY=:1 xdotool key ctrl+a
    sleep 0.1
    DISPLAY=:1 xdotool type --clearmodifiers "$ADMIN_USER"
    sleep 0.5

    # Tab to password field
    DISPLAY=:1 xdotool key Tab
    sleep 0.3
    DISPLAY=:1 xdotool type --clearmodifiers "$ADMIN_PASS"
    sleep 0.5

    # Press Enter to submit
    DISPLAY=:1 xdotool key Return

    # Wait for dashboard to load
    echo "Waiting for dashboard to load..."
    sleep 10
fi

# Record start time
date +%s > /tmp/task_start_time.txt

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Soft Launch Configuration Setup Complete ==="
echo ""
echo "If not already logged in, use: admin / Admin1234!"
echo ""