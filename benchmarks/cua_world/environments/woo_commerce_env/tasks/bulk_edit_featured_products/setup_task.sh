#!/bin/bash
# Setup script for Bulk Edit Featured Products task

echo "=== Setting up Bulk Edit Featured Products Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Ensure Database Connection
if ! check_db_connection; then
    echo "ERROR: Database not reachable. Cannot set up task."
    exit 1
fi

# 2. Reset State: Un-feature ALL products to ensure a clean slate
echo "Clearing 'featured' status from all products..."

# Get term_taxonomy_id for 'featured' in 'product_visibility' taxonomy
FEATURED_TERM_ID=$(wc_query "SELECT tt.term_taxonomy_id 
    FROM wp_terms t 
    JOIN wp_term_taxonomy tt ON t.term_id = tt.term_id 
    WHERE t.slug = 'featured' AND tt.taxonomy = 'product_visibility' LIMIT 1")

if [ -n "$FEATURED_TERM_ID" ]; then
    # Delete relationships for this term
    wc_query "DELETE FROM wp_term_relationships WHERE term_taxonomy_id = $FEATURED_TERM_ID"
    # Reset count in taxonomy table (optional but good for consistency)
    wc_query "UPDATE wp_term_taxonomy SET count = 0 WHERE term_taxonomy_id = $FEATURED_TERM_ID"
    echo "Cleared featured status (Term ID: $FEATURED_TERM_ID)."
else
    echo "WARNING: 'featured' term not found in database. Initial state might be inconsistent."
fi

# 3. Verify target products exist
echo "Verifying target products exist..."
MISSING_PRODUCTS=0
for sku in "WBH-001" "OCT-BLK-M" "MWS-GRY-L"; do
    PROD=$(get_product_by_sku "$sku")
    if [ -z "$PROD" ]; then
        echo "ERROR: Required product SKU '$sku' not found!"
        MISSING_PRODUCTS=1
    else
        echo "Found product: $sku"
    fi
done

if [ "$MISSING_PRODUCTS" -eq 1 ]; then
    echo "FATAL: Missing required products for task."
    exit 1
fi

# 4. Record initial featured count (should be 0)
INITIAL_COUNT=$(wc_query "SELECT COUNT(*) FROM wp_term_relationships WHERE term_taxonomy_id = '$FEATURED_TERM_ID'")
echo "$INITIAL_COUNT" > /tmp/initial_featured_count
echo "Initial featured product count: $INITIAL_COUNT"

# 5. Launch Firefox to Products Page
echo "Launching Firefox to Products list..."

# Ensure WordPress is reachable
if ! ensure_wordpress_shown 60; then
    echo "FATAL: Could not load WordPress admin page."
    exit 1
fi

# Navigate explicitly to the product list page
su - ga -c "DISPLAY=:1 firefox 'http://localhost/wp-admin/edit.php?post_type=product' &"
sleep 5

# Focus and maximize
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    maximize_window "$WID"
fi

# 6. Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="