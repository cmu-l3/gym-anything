#!/bin/bash
echo "=== Setting up Product Catalog Reorganization Task ==="

source /workspace/scripts/task_utils.sh

# Clean up any pre-existing test artifacts

# Remove 'Outdoor & Recreation', 'Camping Gear', 'Fitness Equipment' categories
for CAT_NAME in "outdoor & recreation" "camping gear" "fitness equipment"; do
    CAT_ID=$(wc_query "SELECT t.term_id FROM wp_terms t JOIN wp_term_taxonomy tt ON t.term_id = tt.term_id WHERE tt.taxonomy='product_cat' AND LOWER(t.name)='$CAT_NAME' LIMIT 1" 2>/dev/null)
    if [ -n "$CAT_ID" ]; then
        wc_query "DELETE tr FROM wp_term_relationships tr JOIN wp_term_taxonomy tt ON tr.term_taxonomy_id = tt.term_taxonomy_id WHERE tt.term_id=$CAT_ID AND tt.taxonomy='product_cat'" 2>/dev/null
        wc_query "DELETE FROM wp_term_taxonomy WHERE term_id=$CAT_ID AND taxonomy='product_cat'" 2>/dev/null
        wc_query "DELETE FROM wp_terms WHERE term_id=$CAT_ID" 2>/dev/null
        echo "Removed pre-existing category: $CAT_NAME"
    fi
done

# Remove pre-existing tags: bestseller, eco-friendly, gift-idea
for TAG_NAME in "bestseller" "eco-friendly" "gift-idea"; do
    TAG_ID=$(wc_query "SELECT t.term_id FROM wp_terms t JOIN wp_term_taxonomy tt ON t.term_id = tt.term_id WHERE tt.taxonomy='product_tag' AND LOWER(t.name)='$TAG_NAME' LIMIT 1" 2>/dev/null)
    if [ -n "$TAG_ID" ]; then
        wc_query "DELETE tr FROM wp_term_relationships tr JOIN wp_term_taxonomy tt ON tr.term_taxonomy_id = tt.term_taxonomy_id WHERE tt.term_id=$TAG_ID AND tt.taxonomy='product_tag'" 2>/dev/null
        wc_query "DELETE FROM wp_term_taxonomy WHERE term_id=$TAG_ID AND taxonomy='product_tag'" 2>/dev/null
        wc_query "DELETE FROM wp_terms WHERE term_id=$TAG_ID" 2>/dev/null
        echo "Removed pre-existing tag: $TAG_NAME"
    fi
done

# Remove featured status from target products
for SKU in "WBH-001" "YMP-001"; do
    PRODUCT_ID=$(wc_query "SELECT post_id FROM wp_postmeta WHERE meta_key='_sku' AND meta_value='$SKU' LIMIT 1" 2>/dev/null)
    if [ -n "$PRODUCT_ID" ]; then
        # Remove product_visibility 'featured' term relationship
        FEATURED_TERM_TAX_ID=$(wc_query "SELECT tt.term_taxonomy_id FROM wp_terms t JOIN wp_term_taxonomy tt ON t.term_id = tt.term_id WHERE t.slug='featured' AND tt.taxonomy='product_visibility' LIMIT 1" 2>/dev/null)
        if [ -n "$FEATURED_TERM_TAX_ID" ]; then
            wc_query "DELETE FROM wp_term_relationships WHERE object_id=$PRODUCT_ID AND term_taxonomy_id=$FEATURED_TERM_TAX_ID" 2>/dev/null
        fi
        echo "Cleared featured status for $SKU"
    fi
done

# Clear short description of PCH-DUO
PCH_ID=$(wc_query "SELECT post_id FROM wp_postmeta WHERE meta_key='_sku' AND meta_value='PCH-DUO' LIMIT 1" 2>/dev/null)
if [ -n "$PCH_ID" ]; then
    wc_query "UPDATE wp_posts SET post_excerpt='' WHERE ID=$PCH_ID" 2>/dev/null
    echo "Cleared short description for PCH-DUO"
fi

# Record timestamp after cleanup
date +%s > /tmp/product_catalog_reorg_start_ts

# Verify prerequisite products exist
echo "Verifying prerequisite products..."
for SKU in "WBH-001" "YMP-001" "RBS-005" "PCH-DUO" "OCT-BLK-M" "BCB-SET2" "LED-DL-01" "CPP-SET3"; do
    DATA=$(get_product_by_sku "$SKU" 2>/dev/null)
    echo "Product $SKU: $([ -n "$DATA" ] && echo "FOUND" || echo "NOT FOUND")"
done

# Ensure WordPress admin page is displayed
echo "Ensuring WordPress admin page is displayed..."
if ! ensure_wordpress_shown 60; then
    echo "FATAL: Could not load WordPress admin page"
    exit 1
fi
echo "WordPress admin page confirmed loaded"

WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
fi

take_screenshot /tmp/product_catalog_reorg_start_screenshot.png

echo "=== Product Catalog Reorganization Task Setup Complete ==="
