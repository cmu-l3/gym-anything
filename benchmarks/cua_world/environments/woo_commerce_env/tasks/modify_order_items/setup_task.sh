#!/bin/bash
# Setup script for Modify Order Items task

echo "=== Setting up Modify Order Items Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Ensure Customer Exists
echo "Ensuring customer Michael Chen exists..."
CUSTOMER_ID=$(wc_query "SELECT ID FROM wp_users WHERE user_email = 'michael.chen@example.com'" 2>/dev/null)

if [ -z "$CUSTOMER_ID" ]; then
    echo "Creating customer Michael Chen..."
    wp user create michael.chen@example.com michael.chen --role=customer --first_name="Michael" --last_name="Chen" --user_pass="password123" --allow-root > /dev/null
    CUSTOMER_ID=$(wc_query "SELECT ID FROM wp_users WHERE user_email = 'michael.chen@example.com'" 2>/dev/null)
fi
echo "Customer ID: $CUSTOMER_ID"

# 2. Ensure Products Exist
echo "Verifying products..."
TSHIRT_ID=$(wc_query "SELECT ID FROM wp_posts WHERE post_title = 'Organic Cotton T-Shirt' AND post_type='product' LIMIT 1" 2>/dev/null)
SWEATER_ID=$(wc_query "SELECT ID FROM wp_posts WHERE post_title = 'Merino Wool Sweater' AND post_type='product' LIMIT 1" 2>/dev/null)

if [ -z "$TSHIRT_ID" ] || [ -z "$SWEATER_ID" ]; then
    echo "ERROR: Required products not found. Re-seeding might be required."
    # Attempt to create if missing (fallback)
    if [ -z "$TSHIRT_ID" ]; then
        TSHIRT_ID=$(wp wc product create --name="Organic Cotton T-Shirt" --sku="OCT-BLK-M" --regular_price="24.99" --type=simple --user=admin --porcelain --allow-root)
    fi
    if [ -z "$SWEATER_ID" ]; then
        SWEATER_ID=$(wp wc product create --name="Merino Wool Sweater" --sku="MWS-GRY-L" --regular_price="89.99" --type=simple --user=admin --porcelain --allow-root)
    fi
fi
echo "T-Shirt ID: $TSHIRT_ID, Sweater ID: $SWEATER_ID"

# 3. Create the Target Order
echo "Creating 'On Hold' order for Michael Chen..."
# We use wp eval to create a specific order state programmatically
ORDER_ID=$(docker exec woocommerce-mariadb wp eval --allow-root "
    \$order = wc_create_order(array('customer_id' => $CUSTOMER_ID));
    \$product = wc_get_product($TSHIRT_ID);
    \$order->add_product(\$product, 1);
    \$address = array(
        'first_name' => 'Michael',
        'last_name'  => 'Chen',
        'email'      => 'michael.chen@example.com',
        'address_1'  => '123 Market St',
        'city'       => 'San Francisco',
        'state'      => 'CA',
        'postcode'   => '94105',
        'country'    => 'US'
    );
    \$order->set_address(\$address, 'billing');
    \$order->set_address(\$address, 'shipping');
    \$order->set_status('on-hold');
    \$order->calculate_totals();
    \$order->save();
    echo \$order->get_id();
" 2>/dev/null)

if [ -z "$ORDER_ID" ]; then
    echo "FATAL: Failed to create setup order."
    exit 1
fi

echo "$ORDER_ID" > /tmp/target_order_id.txt
echo "Created Order ID: $ORDER_ID"

# Record initial total for comparison later
INITIAL_TOTAL=$(wc_query "SELECT meta_value FROM wp_postmeta WHERE post_id=$ORDER_ID AND meta_key='_order_total'" 2>/dev/null)
echo "$INITIAL_TOTAL" > /tmp/initial_order_total.txt

# 4. Prepare Environment
# Ensure WordPress admin is displayed
echo "Ensuring WordPress admin page is displayed..."
if ! ensure_wordpress_shown 60; then
    echo "FATAL: Could not load WordPress admin page."
    exit 1
fi

# Focus Firefox
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="