#!/bin/bash
# Setup script for GDPR Data Erasure task

echo "=== Setting up GDPR Data Erasure Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Reset Privacy Settings to Default (Don't remove order data)
# This ensures the agent must explicitly enable it.
echo "Resetting privacy settings..."
wc_query "UPDATE wp_options SET option_value='no' WHERE option_name='woocommerce_erasure_request_removes_order_data'"
wc_query "INSERT INTO wp_options (option_name, option_value, autoload) VALUES ('woocommerce_erasure_request_removes_order_data', 'no', 'yes') ON DUPLICATE KEY UPDATE option_value='no'"

# 2. Create the Customer "Sarah Connor"
TARGET_EMAIL="sarah.connor.privacy@example.com"
echo "Creating customer: $TARGET_EMAIL"

# Delete if exists to ensure clean state
EXISTING_ID=$(wc_query "SELECT ID FROM wp_users WHERE user_email='$TARGET_EMAIL'")
if [ -n "$EXISTING_ID" ]; then
    wp user delete "$EXISTING_ID" --reassign=1 --yes --allow-root 2>/dev/null
fi

# Create user via WP-CLI
USER_ID=$(wp user create "sarahconnor" "$TARGET_EMAIL" --role="customer" --first_name="Sarah" --last_name="Connor" --user_pass="Terminator1984!" --porcelain --allow-root)
echo "Created User ID: $USER_ID"

# 3. Create a dummy order for this customer
# We need an order to verify that order data anonymization actually happens.
echo "Creating order for User ID: $USER_ID"

# Insert order post
wc_query "INSERT INTO wp_posts (post_author, post_date, post_date_gmt, post_content, post_title, post_status, post_type, ping_status, post_name, post_modified, post_modified_gmt) VALUES (1, NOW(), NOW(), '', 'Order &ndash; ' || NOW(), 'wc-completed', 'shop_order', 'closed', 'order-' || UNIX_TIMESTAMP(), NOW(), NOW())"
ORDER_ID=$(wc_query "SELECT MAX(ID) FROM wp_posts WHERE post_type='shop_order'")

# Add meta data linking order to customer
wc_query "INSERT INTO wp_postmeta (post_id, meta_key, meta_value) VALUES ($ORDER_ID, '_customer_user', '$USER_ID')"
wc_query "INSERT INTO wp_postmeta (post_id, meta_key, meta_value) VALUES ($ORDER_ID, '_billing_first_name', 'Sarah')"
wc_query "INSERT INTO wp_postmeta (post_id, meta_key, meta_value) VALUES ($ORDER_ID, '_billing_last_name', 'Connor')"
wc_query "INSERT INTO wp_postmeta (post_id, meta_key, meta_value) VALUES ($ORDER_ID, '_billing_address_1', '123 Tech Blvd')"
wc_query "INSERT INTO wp_postmeta (post_id, meta_key, meta_value) VALUES ($ORDER_ID, '_billing_city', 'Los Angeles')"
wc_query "INSERT INTO wp_postmeta (post_id, meta_key, meta_value) VALUES ($ORDER_ID, '_billing_email', '$TARGET_EMAIL')"
wc_query "INSERT INTO wp_postmeta (post_id, meta_key, meta_value) VALUES ($ORDER_ID, '_order_total', '150.00')"

echo "Created Order ID: $ORDER_ID"
echo "$ORDER_ID" > /tmp/target_order_id.txt

# 4. Ensure WordPress admin is loaded
echo "Ensuring WordPress admin page is displayed..."
if ! ensure_wordpress_shown 60; then
    echo "FATAL: Could not load WordPress admin page."
    exit 1
fi

# Focus and maximize Firefox
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
fi

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png
echo "Setup complete. Agent target: $TARGET_EMAIL"