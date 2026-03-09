#!/bin/bash
# Setup script for Create Variable Product task

echo "=== Setting up Create Variable Product Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. Record Task Start Time
date +%s > /tmp/task_start_time.txt

# 2. Clean up environment (delete target product if it exists from previous run)
echo "Checking for existing product..."
EXISTING_ID=$(wc_query "SELECT ID FROM wp_posts WHERE post_title='Handcrafted Ceramic Mug' AND post_type='product' LIMIT 1" 2>/dev/null)

if [ -n "$EXISTING_ID" ]; then
    echo "Removing existing product (ID: $EXISTING_ID)..."
    # Delete parent and children
    wc_query "DELETE FROM wp_posts WHERE ID=$EXISTING_ID OR post_parent=$EXISTING_ID"
    wc_query "DELETE FROM wp_postmeta WHERE post_id=$EXISTING_ID OR post_id IN (SELECT ID FROM wp_posts WHERE post_parent=$EXISTING_ID)"
    wc_query "DELETE FROM wp_term_relationships WHERE object_id=$EXISTING_ID"
fi

# 3. Ensure Category Exists
ACCESSORIES_CAT=$(get_category_by_name "Accessories")
if [ -z "$ACCESSORIES_CAT" ]; then
    echo "Creating Accessories category..."
    # Use WP-CLI for clean category creation
    su - ga -c "wp wc product_cat create --name='Accessories' --user=admin --path=/var/www/html/wordpress" > /dev/null 2>&1 || true
fi

# 4. Record Initial State
INITIAL_PRODUCT_COUNT=$(get_product_count 2>/dev/null || echo "0")
echo "$INITIAL_PRODUCT_COUNT" > /tmp/initial_product_count.txt

# 5. Launch Application
echo "Ensuring WordPress admin page is displayed..."
if ! ensure_wordpress_shown 60; then
    echo "FATAL: Could not load WordPress admin page - task cannot proceed"
    exit 1
fi

# 6. Window Management
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
fi

# 7. Initial Screenshot
take_screenshot /tmp/task_initial.png
echo "Initial setup complete."