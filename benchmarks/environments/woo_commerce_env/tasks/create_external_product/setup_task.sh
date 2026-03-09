#!/bin/bash
set -e
echo "=== Setting up create_external_product task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Record initial product count for anti-gaming
INITIAL_COUNT=$(get_product_count 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_product_count.txt
echo "Initial product count: $INITIAL_COUNT"

# Verify database connectivity
if ! check_db_connection; then
    echo "ERROR: Cannot connect to database. Aborting setup."
    exit 1
fi

# Verify that "Electronics" category exists
ELECTRONICS_CAT=$(get_category_by_name "Electronics")
if [ -z "$ELECTRONICS_CAT" ]; then
    echo "Electronics category not found, creating it..."
    cd /var/www/html/wordpress
    wp wc product_cat create --name="Electronics" --description="Electronic devices and accessories" --user=admin --allow-root 2>&1
fi
echo "Electronics category verified."

# Remove any pre-existing product with the target SKU (clean state)
EXISTING=$(get_product_by_sku "EXT-SONY-WH1000XM5")
if [ -n "$EXISTING" ]; then
    EXISTING_ID=$(echo "$EXISTING" | awk '{print $1}')
    echo "Removing pre-existing product with SKU EXT-SONY-WH1000XM5 (ID: $EXISTING_ID)..."
    cd /var/www/html/wordpress
    wp post delete "$EXISTING_ID" --force --allow-root 2>&1 || true
fi

# Remove any pre-existing product with similar name
EXISTING_NAME=$(get_product_by_name "Sony WH-1000XM5")
if [ -n "$EXISTING_NAME" ]; then
    EXISTING_NAME_ID=$(echo "$EXISTING_NAME" | awk '{print $1}')
    echo "Removing pre-existing product with name containing Sony WH-1000XM5 (ID: $EXISTING_NAME_ID)..."
    cd /var/www/html/wordpress
    wp post delete "$EXISTING_NAME_ID" --force --allow-root 2>&1 || true
fi

# Re-record product count after cleanup
CLEAN_COUNT=$(get_product_count 2>/dev/null || echo "0")
echo "$CLEAN_COUNT" > /tmp/initial_product_count.txt
echo "Clean product count: $CLEAN_COUNT"

# Ensure Apache is running
systemctl restart apache2
sleep 2

# Launch Firefox to WooCommerce admin dashboard
echo "Launching Firefox..."
pkill -f firefox 2>/dev/null || true
sleep 2

su - ga -c "DISPLAY=:1 firefox --no-remote 'http://localhost/wp-admin/' &"
sleep 8

# Wait for Firefox window to appear
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i -E "firefox|mozilla|wordpress|woocommerce|dashboard"; then
        echo "Firefox window detected."
        break
    fi
    sleep 1
done

# Maximize Firefox
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 2

# Take screenshot of initial state
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="