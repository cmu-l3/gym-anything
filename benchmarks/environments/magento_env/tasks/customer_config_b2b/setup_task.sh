#!/bin/bash
# Setup script for Customer Config B2B task

echo "=== Setting up Customer Config Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Admin credentials
ADMIN_USER="admin"
ADMIN_PASS="Admin1234!"

# 1. Reset configuration to known defaults to ensure task requires action
# We use magento CLI for reliability, though it might be slow.
# If CLI fails/locks, we fall back to direct DB updates (handled by cache clean later)

echo "Resetting customer configuration to defaults..."

# Helper to set config via DB to avoid CLI overhead/locks if possible
# (Magento config is stored in core_config_data)
set_db_config() {
    local path="$1"
    local value="$2"
    # Insert or update (on duplicate key update)
    # Scope is default (scope='default', scope_id=0)
    magento_query "INSERT INTO core_config_data (scope, scope_id, path, value) VALUES ('default', 0, '$path', '$value') ON DUPLICATE KEY UPDATE value='$value'"
}

# Reset Address Lines to 2
set_db_config "customer/address/street_lines" "2"

# Reset Tax/VAT to Optional (opt) or No (0/empty) - setting to 'opt'
set_db_config "customer/address/taxvat_show" ""

# Reset DOB to Optional
set_db_config "customer/address/dob_show" ""

# Reset Email Sender to General Contact
set_db_config "customer/create_account/email_identity" "general"

# Reset Password Length to 8
set_db_config "customer/password/minimum_password_length" "8"

# Reset Character Classes to 3
set_db_config "customer/password/required_character_classes_number" "3"

# Clear config cache to ensure admin panel reflects DB changes
echo "Flushing config cache..."
cd /var/www/html/magento
php bin/magento cache:clean config > /dev/null 2>&1 || true

# 2. Record Initial State for anti-gaming verification
echo "Recording initial state..."
magento_query "SELECT path, value FROM core_config_data WHERE path LIKE 'customer/%'" > /tmp/initial_config_dump.txt

# Timestamp
date +%s > /tmp/task_start_time.txt

# 3. Ensure Firefox is running and ready
echo "Ensuring Firefox is running..."
MAGENTO_ADMIN_URL="http://localhost/admin"

if ! pgrep -f firefox > /dev/null; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox '$MAGENTO_ADMIN_URL' > /tmp/firefox_task.log 2>&1 &"
    sleep 10
fi

# Wait for Firefox window
wait_for_window "firefox\|mozilla\|Magento" 30

# Focus Firefox window
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 2
fi

# Check for login page and auto-login if needed
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

echo "=== Setup Complete ==="
echo "Configuration reset to defaults."