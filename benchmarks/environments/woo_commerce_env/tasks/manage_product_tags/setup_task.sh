#!/bin/bash
set -e
echo "=== Setting up task: manage_product_tags ==="

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

# 1. Clean up any existing tags with the target names to ensure a fresh start
echo "Cleaning up any pre-existing tags..."
for tag_name in "Premium" "Eco-Friendly" "Gift Idea"; do
    # Find term_id
    TAG_ID=$(wc_query "SELECT t.term_id FROM wp_terms t JOIN wp_term_taxonomy tt ON t.term_id = tt.term_id WHERE tt.taxonomy = 'product_tag' AND LOWER(TRIM(t.name)) = LOWER(TRIM('$tag_name')) LIMIT 1" 2>/dev/null)
    
    if [ -n "$TAG_ID" ]; then
        echo "  Removing pre-existing tag '$tag_name' (ID=$TAG_ID)..."
        # Delete relationships
        wc_query "DELETE FROM wp_term_relationships WHERE term_taxonomy_id IN (SELECT term_taxonomy_id FROM wp_term_taxonomy WHERE term_id=$TAG_ID AND taxonomy='product_tag')" 2>/dev/null || true
        # Delete taxonomy entry
        wc_query "DELETE FROM wp_term_taxonomy WHERE term_id=$TAG_ID AND taxonomy='product_tag'" 2>/dev/null || true
        # Delete term
        wc_query "DELETE FROM wp_terms WHERE term_id=$TAG_ID" 2>/dev/null || true
    fi
done

# 2. Verify required products exist; create if missing
echo "Verifying required products exist..."
PRODUCT1=$(wc_query "SELECT ID FROM wp_posts WHERE post_type='product' AND post_status='publish' AND post_title LIKE '%Organic Cotton T-Shirt%' LIMIT 1")
if [ -z "$PRODUCT1" ]; then
    echo "Creating missing product: Organic Cotton T-Shirt"
    wp wc product create --name="Organic Cotton T-Shirt" --sku="OCT-BLK-M" --regular_price="24.99" --type="simple" --status="publish" --description="Soft organic cotton t-shirt." --user=admin --allow-root >/dev/null 2>&1
fi

PRODUCT2=$(wc_query "SELECT ID FROM wp_posts WHERE post_type='product' AND post_status='publish' AND post_title LIKE '%Wireless Bluetooth Headphones%' LIMIT 1")
if [ -z "$PRODUCT2" ]; then
    echo "Creating missing product: Wireless Bluetooth Headphones"
    wp wc product create --name="Wireless Bluetooth Headphones" --sku="WBH-001" --regular_price="79.99" --type="simple" --status="publish" --description="Premium wireless headphones." --user=admin --allow-root >/dev/null 2>&1
fi

PRODUCT3=$(wc_query "SELECT ID FROM wp_posts WHERE post_type='product' AND post_status='publish' AND post_title LIKE '%Merino Wool Sweater%' LIMIT 1")
if [ -z "$PRODUCT3" ]; then
    echo "Creating missing product: Merino Wool Sweater"
    wp wc product create --name="Merino Wool Sweater" --sku="MWS-GRY-L" --regular_price="89.99" --type="simple" --status="publish" --description="Luxurious merino wool sweater." --user=admin --allow-root >/dev/null 2>&1
fi

# 3. Record initial product tag count (for anti-gaming)
INITIAL_TAG_COUNT=$(wc_query "SELECT COUNT(*) FROM wp_terms t JOIN wp_term_taxonomy tt ON t.term_id = tt.term_id WHERE tt.taxonomy = 'product_tag'" 2>/dev/null || echo "0")
echo "$INITIAL_TAG_COUNT" > /tmp/initial_tag_count.txt
echo "Initial product tag count: $INITIAL_TAG_COUNT"

# 4. Prepare Browser
# Ensure WordPress admin page is showing
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
take_screenshot /tmp/task_start_screenshot.png

echo "=== Task setup complete ==="