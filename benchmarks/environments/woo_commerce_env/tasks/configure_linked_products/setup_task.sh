#!/bin/bash
set -e
echo "=== Setting up configure_linked_products task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Verify database is accessible
if ! check_db_connection; then
    echo "ERROR: Database connection failed"
    exit 1
fi

# Get product IDs by SKU to ensure they exist and for cleaning
echo "Resolving product IDs..."
TARGET_ID=$(wc_query "SELECT p.ID FROM wp_posts p JOIN wp_postmeta pm ON p.ID = pm.post_id WHERE pm.meta_key='_sku' AND pm.meta_value='USBC-065' AND p.post_type='product' LIMIT 1")
UPSELL_ID=$(wc_query "SELECT p.ID FROM wp_posts p JOIN wp_postmeta pm ON p.ID = pm.post_id WHERE pm.meta_key='_sku' AND pm.meta_value='WBH-001' AND p.post_type='product' LIMIT 1")
CROSS1_ID=$(wc_query "SELECT p.ID FROM wp_posts p JOIN wp_postmeta pm ON p.ID = pm.post_id WHERE pm.meta_key='_sku' AND pm.meta_value='OCT-BLK-M' AND p.post_type='product' LIMIT 1")
CROSS2_ID=$(wc_query "SELECT p.ID FROM wp_posts p JOIN wp_postmeta pm ON p.ID = pm.post_id WHERE pm.meta_key='_sku' AND pm.meta_value='SFDJ-BLU-32' AND p.post_type='product' LIMIT 1")

if [ -z "$TARGET_ID" ] || [ -z "$UPSELL_ID" ] || [ -z "$CROSS1_ID" ] || [ -z "$CROSS2_ID" ]; then
    echo "ERROR: Missing required products."
    echo "Target: $TARGET_ID, Upsell: $UPSELL_ID, Cross1: $CROSS1_ID, Cross2: $CROSS2_ID"
    # Attempt to create them or fail? For now, we assume the env setup script created them.
    # If missing, we can't proceed.
    exit 1
fi

echo "Target ID: $TARGET_ID"

# Clean existing linked products to ensure fresh start
echo "Clearing existing linked products..."
cd /var/www/html/wordpress
# Use WP-CLI to clear meta
wp post meta update "$TARGET_ID" _upsell_ids "" --allow-root 2>/dev/null || true
wp post meta update "$TARGET_ID" _crosssell_ids "" --allow-root 2>/dev/null || true

# Verify clean state
INITIAL_UPSELLS=$(wc_query "SELECT meta_value FROM wp_postmeta WHERE post_id=$TARGET_ID AND meta_key='_upsell_ids'")
INITIAL_CROSSSELLS=$(wc_query "SELECT meta_value FROM wp_postmeta WHERE post_id=$TARGET_ID AND meta_key='_crosssell_ids'")

# Launch Firefox
echo "Launching Firefox..."
pkill -f firefox 2>/dev/null || true

# We navigate to the product list, not the edit page directly, to force navigation
su - ga -c "DISPLAY=:1 firefox 'http://localhost/wp-admin/edit.php?post_type=product' &"

# Wait for window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i -E "firefox|mozilla|products"; then
        echo "Firefox window detected"
        break
    fi
    sleep 1
done

# Maximize
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 2

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="