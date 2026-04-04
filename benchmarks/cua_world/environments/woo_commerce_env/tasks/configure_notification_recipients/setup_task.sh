#!/bin/bash
# Setup script for Configure Notification Recipients task

echo "=== Setting up Configure Notification Recipients Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Reset email settings to default (admin@example.com) to ensure clean state
# This ensures the task is repeatable and the "change detection" works
echo "Resetting email settings to defaults..."
DEFAULT_RECIPIENT="admin@example.com"

# Using WP-CLI to reset settings
# Note: These are stored as serialized arrays in wp_options. 
# We update the specific 'recipient' key within the array.
# Since manipulating serialized data via SQL is risky, we use a small PHP snippet via WP-CLI eval
cd /var/www/html/wordpress

wp eval '
    $settings = ["woocommerce_new_order_settings", "woocommerce_cancelled_order_settings", "woocommerce_failed_order_settings"];
    foreach($settings as $opt) {
        $val = get_option($opt);
        if(is_array($val)) {
            $val["recipient"] = "'"$DEFAULT_RECIPIENT"'";
            update_option($opt, $val);
        }
    }
' --allow-root

# Record initial state for verification
echo "Recording initial state..."
INITIAL_NEW_ORDER=$(wp option get woocommerce_new_order_settings --format=json --allow-root | jq -r '.recipient')
INITIAL_CANCELLED=$(wp option get woocommerce_cancelled_order_settings --format=json --allow-root | jq -r '.recipient')
INITIAL_FAILED=$(wp option get woocommerce_failed_order_settings --format=json --allow-root | jq -r '.recipient')

cat > /tmp/initial_state.json << EOF
{
    "new_order": "$INITIAL_NEW_ORDER",
    "cancelled_order": "$INITIAL_CANCELLED",
    "failed_order": "$INITIAL_FAILED"
}
EOF

# CRITICAL: Ensure WordPress admin page is showing
echo "Ensuring WordPress admin page is displayed..."
if ! ensure_wordpress_shown 60; then
    echo "FATAL: Could not load WordPress admin page - task cannot proceed"
    exit 1
fi

# Focus and maximize Firefox window
echo "Focusing Firefox window..."
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
fi

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="