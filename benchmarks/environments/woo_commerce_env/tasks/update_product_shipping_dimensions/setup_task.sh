#!/bin/bash
set -e
echo "=== Setting up Task: Update Product Shipping Dimensions ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record start time
date +%s > /tmp/task_start_time.txt

# Wait for database connection
echo "Waiting for database..."
for i in {1..30}; do
    if check_db_connection; then
        echo "Database connected."
        break
    fi
    sleep 2
done

# 1. Configure Global Unit Settings (kg/cm)
# This ensures the UI labels match the task description
echo "Configuring unit settings..."
wp option update woocommerce_weight_unit "kg" --allow-root
wp option update woocommerce_dimension_unit "cm" --allow-root

# 2. Prepare Target Products
# Delete if they exist to ensure clean state (idempotency)
echo "Cleaning up old products..."
wp post delete $(wp post list --post_type=product --name="oak-coffee-table" --field=ID --allow-root) --force --allow-root 2>/dev/null || true
wp post delete $(wp post list --post_type=product --name="ceramic-vase" --field=ID --allow-root) --force --allow-root 2>/dev/null || true
wp post delete $(wp post list --post_type=product --name="linen-curtains" --field=ID --allow-root) --force --allow-root 2>/dev/null || true

# Create products with empty/zero shipping data
echo "Creating target products..."

# Oak Coffee Table
wp wc product create \
    --name="Oak Coffee Table" \
    --sku="FURN-OCT-001" \
    --regular_price="249.00" \
    --description="Solid oak coffee table with clear lacquer finish." \
    --user=admin \
    --allow-root > /dev/null

# Ceramic Vase
wp wc product create \
    --name="Ceramic Vase" \
    --sku="DECOR-VASE-002" \
    --regular_price="45.00" \
    --description="Hand-thrown ceramic vase, blue glaze." \
    --user=admin \
    --allow-root > /dev/null

# Linen Curtains
wp wc product create \
    --name="Linen Curtains" \
    --sku="HOME-CURT-003" \
    --regular_price="89.00" \
    --description="100% natural linen curtains, set of 2." \
    --user=admin \
    --allow-root > /dev/null

# Explicitly clear meta to ensure "Do Nothing" fails
# (wp wc product create might set defaults, so we force empty strings)
echo "Clearing shipping meta..."
for sku in "FURN-OCT-001" "DECOR-VASE-002" "HOME-CURT-003"; do
    PID=$(get_product_by_sku "$sku" | cut -f1)
    if [ -n "$PID" ]; then
        wp post meta update "$PID" _weight "" --allow-root
        wp post meta update "$PID" _length "" --allow-root
        wp post meta update "$PID" _width "" --allow-root
        wp post meta update "$PID" _height "" --allow-root
    fi
done

# 3. Application Setup (Firefox)
# Ensure WordPress admin is loaded and ready
echo "Ensuring WordPress admin is displayed..."
if ! ensure_wordpress_shown 60; then
    echo "FATAL: WordPress admin not loading."
    exit 1
fi

# Navigate Firefox to the "All Products" page to start
echo "Navigating to Products list..."
su - ga -c "DISPLAY=:1 firefox 'http://localhost/wp-admin/edit.php?post_type=product' &"
sleep 5

# Focus and maximize
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Capture initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="