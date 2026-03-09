#!/bin/bash
set -e
echo "=== Setting up task: process_partial_refund ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

WP_DIR="/var/www/html/wordpress"
cd "$WP_DIR"

# ============================================================
# 1. Look up product IDs by SKU
# ============================================================
echo "Looking up product IDs..."

# Get IDs for Headphones (WBH-001) and Charger (USBC-065)
HEADPHONES_ID=$(wc_query "SELECT p.ID FROM wp_posts p JOIN wp_postmeta pm ON p.ID = pm.post_id WHERE p.post_type='product' AND pm.meta_key='_sku' AND pm.meta_value='WBH-001' LIMIT 1")
CHARGER_ID=$(wc_query "SELECT p.ID FROM wp_posts p JOIN wp_postmeta pm ON p.ID = pm.post_id WHERE p.post_type='product' AND pm.meta_key='_sku' AND pm.meta_value='USBC-065' LIMIT 1")

if [ -z "$HEADPHONES_ID" ] || [ -z "$CHARGER_ID" ]; then
    echo "ERROR: Could not find required products. HEADPHONES_ID=$HEADPHONES_ID, CHARGER_ID=$CHARGER_ID"
    # Fallback to creating them if missing (should be there from env setup)
    exit 1
fi
echo "Headphones product ID: $HEADPHONES_ID"
echo "Charger product ID: $CHARGER_ID"

# ============================================================
# 2. Look up or Create Emily Davis customer
# ============================================================
echo "Looking up Emily Davis customer..."

EMILY_ID=$(wc_query "SELECT u.ID FROM wp_users u JOIN wp_usermeta fn ON u.ID=fn.user_id AND fn.meta_key='first_name' JOIN wp_usermeta ln ON u.ID=ln.user_id AND ln.meta_key='last_name' WHERE fn.meta_value='Emily' AND ln.meta_value='Davis' LIMIT 1")

if [ -z "$EMILY_ID" ]; then
    echo "Emily Davis not found, creating customer..."
    EMILY_ID=$(wp user create emily.davis emily.davis@example.com --role=customer --first_name=Emily --last_name=Davis --user_pass=Customer123! --allow-root --porcelain 2>/dev/null || true)
    # Get ID if porcelain output failed
    if [ -z "$EMILY_ID" ] || [ "$EMILY_ID" = "Error: This username is already registered." ]; then
         EMILY_ID=$(wp user get emily.davis --field=ID --allow-root 2>/dev/null)
    fi
fi
echo "Emily Davis user ID: $EMILY_ID"

# ============================================================
# 3. Create the target order via WP-CLI
# ============================================================
echo "Creating target order..."

# Create order with 2 items
ORDER_JSON=$(wp wc shop_order create \
    --status=completed \
    --customer_id="$EMILY_ID" \
    --billing='{"first_name":"Emily","last_name":"Davis","email":"emily.davis@example.com","address_1":"456 Oak Avenue","city":"Portland","state":"OR","postcode":"97201","country":"US"}' \
    --shipping='{"first_name":"Emily","last_name":"Davis","address_1":"456 Oak Avenue","city":"Portland","state":"OR","postcode":"97201","country":"US"}' \
    --line_items="[{\"product_id\":$HEADPHONES_ID,\"quantity\":1},{\"product_id\":$CHARGER_ID,\"quantity\":1}]" \
    --user=admin --allow-root --porcelain 2>/dev/null)

ORDER_ID="$ORDER_JSON"
echo "Created order ID: $ORDER_ID"

if [ -z "$ORDER_ID" ]; then
    echo "ERROR: Failed to create order"
    exit 1
fi

# Save identifiers for verifier (hidden from agent)
echo "$ORDER_ID" > /tmp/target_order_id.txt
echo "$CHARGER_ID" > /tmp/target_charger_product_id.txt
chmod 600 /tmp/target_order_id.txt /tmp/target_charger_product_id.txt

# Record initial refund count for this order (should be 0)
INITIAL_REFUND_COUNT=$(wc_query "SELECT COUNT(*) FROM wp_posts WHERE post_type='shop_order_refund' AND post_parent=$ORDER_ID")
echo "$INITIAL_REFUND_COUNT" > /tmp/initial_refund_count.txt
echo "Initial refund count for order $ORDER_ID: $INITIAL_REFUND_COUNT"

# ============================================================
# 4. Launch Firefox to WooCommerce admin
# ============================================================
echo "Ensuring WordPress admin page is displayed..."
if ! ensure_wordpress_shown 60; then
    echo "FATAL: Could not load WordPress admin page - task cannot proceed"
    exit 1
fi

# Focus and maximize Firefox window
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
fi

# Take initial screenshot
take_screenshot /tmp/task_initial_state.png

echo "=== Task setup complete ==="
echo "Target Order: $ORDER_ID"
echo "Goal: Refund item $CHARGER_ID (Charger) on order $ORDER_ID"