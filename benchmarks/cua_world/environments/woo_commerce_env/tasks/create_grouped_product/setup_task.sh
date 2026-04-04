#!/bin/bash
# Setup script for Create Grouped Product task

echo "=== Setting up Create Grouped Product Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Record initial grouped product count for anti-gaming verification
# We count products that have the term 'grouped' in taxonomy 'product_type'
echo "Recording initial grouped product count..."
INITIAL_COUNT=$(wc_query "SELECT COUNT(*) FROM wp_posts p
    JOIN wp_term_relationships tr ON p.ID = tr.object_id
    JOIN wp_term_taxonomy tt ON tr.term_taxonomy_id = tt.term_taxonomy_id
    JOIN wp_terms t ON tt.term_id = t.term_id
    WHERE p.post_type = 'product' AND p.post_status = 'publish'
    AND t.slug = 'grouped' AND tt.taxonomy = 'product_type'" 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_grouped_count
echo "Initial grouped product count: $INITIAL_COUNT"

# Verify prerequisite products exist (The children to be linked)
echo "Verifying prerequisite products..."
HEADPHONES=$(get_product_by_sku "WBH-001" 2>/dev/null)
CHARGER=$(get_product_by_sku "USBC-065" 2>/dev/null)

if [ -z "$HEADPHONES" ] || [ -z "$CHARGER" ]; then
    echo "WARNING: Prerequisite products (Headphones/Charger) not found. Seeding may have failed."
    # Optional: We could try to create them here if missing, but we rely on env setup
else
    echo "Prerequisite products found."
fi

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

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png
echo "Initial screenshot saved"

echo "=== Setup Complete ==="
echo "Agent should be on the WooCommerce admin dashboard."