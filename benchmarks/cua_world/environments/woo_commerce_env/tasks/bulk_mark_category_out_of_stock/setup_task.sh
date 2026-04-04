#!/bin/bash
# Setup script for Bulk Mark Category Out of Stock task

echo "=== Setting up Bulk Mark Category Out of Stock Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Ensure Database is Ready
if ! check_db_connection; then
    echo "ERROR: Database not accessible."
    exit 1
fi

# 2. Reset Stock Status to Known State (In Stock)
echo "Resetting stock status for verification baseline..."

# Reset Accessories to 'instock'
wc_query "UPDATE wp_postmeta pm
    JOIN wp_term_relationships tr ON pm.post_id = tr.object_id
    JOIN wp_term_taxonomy tt ON tr.term_taxonomy_id = tt.term_taxonomy_id
    JOIN wp_terms t ON tt.term_id = t.term_id
    SET pm.meta_value = 'instock'
    WHERE pm.meta_key = '_stock_status'
    AND t.slug = 'accessories'
    AND tt.taxonomy = 'product_cat'"

# Reset Clothing to 'instock' (Control group)
wc_query "UPDATE wp_postmeta pm
    JOIN wp_term_relationships tr ON pm.post_id = tr.object_id
    JOIN wp_term_taxonomy tt ON tr.term_taxonomy_id = tt.term_taxonomy_id
    JOIN wp_terms t ON tt.term_id = t.term_id
    SET pm.meta_value = 'instock'
    WHERE pm.meta_key = '_stock_status'
    AND t.slug = 'clothing'
    AND tt.taxonomy = 'product_cat'"

# 3. Capture Initial Product IDs for verification
echo "Recording target product IDs..."

# Get IDs of Accessories
ACCESSORIES_IDS=$(wc_query "SELECT GROUP_CONCAT(tr.object_id)
    FROM wp_term_relationships tr
    JOIN wp_term_taxonomy tt ON tr.term_taxonomy_id = tt.term_taxonomy_id
    JOIN wp_terms t ON tt.term_id = t.term_id
    WHERE t.slug = 'accessories' AND tt.taxonomy = 'product_cat'")

# Get IDs of Clothing
CLOTHING_IDS=$(wc_query "SELECT GROUP_CONCAT(tr.object_id)
    FROM wp_term_relationships tr
    JOIN wp_term_taxonomy tt ON tr.term_taxonomy_id = tt.term_taxonomy_id
    JOIN wp_terms t ON tt.term_id = t.term_id
    WHERE t.slug = 'clothing' AND tt.taxonomy = 'product_cat'")

echo "$ACCESSORIES_IDS" > /tmp/target_ids.txt
echo "$CLOTHING_IDS" > /tmp/control_ids.txt

echo "Target IDs (Accessories): $ACCESSORIES_IDS"
echo "Control IDs (Clothing): $CLOTHING_IDS"

# 4. Prepare Browser
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

# Navigate specifically to Products page to save agent one click (optional, but helpful for context)
su - ga -c "DISPLAY=:1 xdotool key ctrl+l"
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool type 'http://localhost/wp-admin/edit.php?post_type=product'"
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key Return"
sleep 5

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="