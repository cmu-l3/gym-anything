#!/bin/bash
# Setup script for Discontinue Product Legacy task

echo "=== Setting up Discontinue Product Legacy Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# CRITICAL: Ensure WordPress admin page is showing
echo "Ensuring WordPress admin page is displayed..."
if ! ensure_wordpress_shown 60; then
    echo "FATAL: Could not load WordPress admin page - task cannot proceed"
    exit 1
fi
echo "WordPress admin page confirmed loaded"

# Focus and maximize Firefox window
echo "Focusing Firefox window..."
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
fi

# ============================================================
# Prepare Target Product Data
# ============================================================
echo "Preparing target product: Vintage Camera Lens..."

# Check if product exists by SKU
EXISTING_ID=$(wc_query "SELECT p.ID FROM wp_posts p JOIN wp_postmeta pm ON p.ID = pm.post_id WHERE p.post_type='product' AND pm.meta_key='_sku' AND pm.meta_value='VCL-50MM' LIMIT 1" 2>/dev/null)

if [ -n "$EXISTING_ID" ]; then
    echo "Product exists (ID: $EXISTING_ID). Resetting state..."
    # Reset status to publish
    wc_query "UPDATE wp_posts SET post_status='publish', post_excerpt='A classic 50mm lens for vintage photography enthusiasts. Sharp optics and manual focus control.' WHERE ID=$EXISTING_ID"
    
    # Reset stock status to instock
    wc_query "UPDATE wp_postmeta SET meta_value='instock' WHERE post_id=$EXISTING_ID AND meta_key='_stock_status'"
    wc_query "UPDATE wp_postmeta SET meta_value='no' WHERE post_id=$EXISTING_ID AND meta_key='_manage_stock'"
    
    # Reset visibility (Remove 'exclude-from-search' and 'exclude-from-catalog' terms)
    # This requires finding the term_taxonomy_ids for those terms and deleting from wp_term_relationships
    # For simplicity, we'll rely on WP-CLI if available or complex SQL, but let's try a direct SQL approach safely
    
    # Get term_taxonomy_ids for visibility terms
    VISIBILITY_TERM_IDS=$(wc_query "SELECT tt.term_taxonomy_id FROM wp_terms t JOIN wp_term_taxonomy tt ON t.term_id = tt.term_id WHERE t.slug IN ('exclude-from-search', 'exclude-from-catalog') AND tt.taxonomy='product_visibility'")
    
    if [ -n "$VISIBILITY_TERM_IDS" ]; then
        # Convert newlines to commas for SQL IN clause
        IDS_CSV=$(echo "$VISIBILITY_TERM_IDS" | tr '\n' ',' | sed 's/,$//')
        if [ -n "$IDS_CSV" ]; then
            wc_query "DELETE FROM wp_term_relationships WHERE object_id=$EXISTING_ID AND term_taxonomy_id IN ($IDS_CSV)"
        fi
    fi
    
else
    echo "Creating new product 'Vintage Camera Lens'..."
    # Create via WP-CLI for reliability
    cd /var/www/html/wordpress
    wp wc product create \
        --name="Vintage Camera Lens" \
        --sku="VCL-50MM" \
        --type="simple" \
        --status="publish" \
        --regular_price="149.99" \
        --short_description="A classic 50mm lens for vintage photography enthusiasts. Sharp optics and manual focus control." \
        --images='[{"src":"http://demo.woothemes.com/woocommerce/wp-content/uploads/sites/56/2013/06/T_2_front.jpg"}]' \
        --user=admin --allow-root > /dev/null
    
    # Ensure visibility is set to visible (default)
fi

# Record ID for export script
PRODUCT_ID=$(wc_query "SELECT p.ID FROM wp_posts p JOIN wp_postmeta pm ON p.ID = pm.post_id WHERE p.post_type='product' AND pm.meta_key='_sku' AND pm.meta_value='VCL-50MM' LIMIT 1" 2>/dev/null)
echo "$PRODUCT_ID" > /tmp/target_product_id
echo "Target Product ID: $PRODUCT_ID"

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="