#!/bin/bash
set -e
echo "=== Setting up task: configure_inventory_settings ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Wait for database
for i in {1..30}; do
    if check_db_connection; then
        break
    fi
    sleep 2
done

# ==============================================================================
# Set Initial State (Force incorrect values so agent must act)
# ==============================================================================
echo "Configuring initial inventory settings to non-target values..."

# Helper to update option
update_option() {
    local name="$1"
    local value="$2"
    wc_query "UPDATE wp_options SET option_value='$value' WHERE option_name='$name'"
    if [ $? -eq 0 ] && [ "$(wc_query "SELECT ROW_COUNT()")" -eq "0" ]; then
        # Insert if not exists
        wc_query "INSERT INTO wp_options (option_name, option_value, autoload) VALUES ('$name', '$value', 'yes')"
    fi
}

# 1. Manage stock: Keep 'yes' (agent just verifies)
update_option "woocommerce_manage_stock" "yes"

# 2. Hold stock: Default is usually 60. Target is 45.
update_option "woocommerce_hold_stock_minutes" "60"

# 3. Notifications: Enable them (agent verifies)
update_option "woocommerce_notify_low_stock" "yes"
update_option "woocommerce_notify_no_stock" "yes"

# 4. Recipient: Set to default admin. Target is warehouse@example.com.
update_option "woocommerce_stock_email_recipient" "admin@example.com"

# 5. Low stock threshold: Set to 2. Target is 10.
update_option "woocommerce_notify_low_stock_amount" "2"

# 6. Out of stock threshold: Set to 0. Target is 2.
update_option "woocommerce_notify_no_stock_amount" "0"

# 7. Visibility: Set to no (show items). Target is yes (hide items).
update_option "woocommerce_hide_out_of_stock_items" "no"

# 8. Display format: Set to empty (always show). Target is 'low_amount'.
update_option "woocommerce_stock_format" ""

echo "Initial settings configured."

# ==============================================================================
# Browser Setup
# ==============================================================================

# Ensure Apache/WordPress is responsive
echo "Checking WordPress availability..."
if ! ensure_wordpress_shown 60; then
    echo "WARNING: WordPress check failed, attempting to restart services..."
    systemctl restart apache2
    sleep 5
fi

# Launch/Focus Firefox on the Dashboard
echo "Launching Firefox to Admin Dashboard..."
pkill -f firefox || true
sleep 1

# Start Firefox
su - ga -c "DISPLAY=:1 firefox --no-remote --new-window 'http://localhost/wp-admin/' &"

# Wait for window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i -E "(firefox|mozilla|WordPress)"; then
        echo "Firefox window detected"
        break
    fi
    sleep 1
done

# Maximize and focus
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 xdotool key --delay 100 Escape 2>/dev/null || true

# Capture initial screenshot
sleep 3
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="