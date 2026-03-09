#!/bin/bash
# Setup script for Optimize Product SEO task

echo "=== Setting up Optimize Product SEO Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Identify Target Products and Record Initial State
# We need to capture the initial state to verify that changes were actually made
echo "Recording initial state of target products..."

# Target 1: Organic Cotton T-Shirt
P1_DATA=$(get_product_by_sku "OCT-BLK-M" 2>/dev/null)
if [ -n "$P1_DATA" ]; then
    P1_ID=$(echo "$P1_DATA" | cut -f1)
    # Get current slug (post_name) and short description (post_excerpt)
    P1_SLUG=$(wc_query "SELECT post_name FROM wp_posts WHERE ID=$P1_ID")
    P1_EXCERPT=$(wc_query "SELECT post_excerpt FROM wp_posts WHERE ID=$P1_ID")
    echo "Product 1 (OCT-BLK-M) found: ID=$P1_ID, Slug='$P1_SLUG'"
else
    echo "ERROR: Product OCT-BLK-M not found"
    exit 1
fi

# Target 2: Wireless Bluetooth Headphones
P2_DATA=$(get_product_by_sku "WBH-001" 2>/dev/null)
if [ -n "$P2_DATA" ]; then
    P2_ID=$(echo "$P2_DATA" | cut -f1)
    P2_SLUG=$(wc_query "SELECT post_name FROM wp_posts WHERE ID=$P2_ID")
    P2_EXCERPT=$(wc_query "SELECT post_excerpt FROM wp_posts WHERE ID=$P2_ID")
    echo "Product 2 (WBH-001) found: ID=$P2_ID, Slug='$P2_SLUG'"
else
    echo "ERROR: Product WBH-001 not found"
    exit 1
fi

# Save initial state to JSON for export script/verifier
cat > /tmp/initial_seo_state.json << EOF
{
    "p1": {
        "id": "$P1_ID",
        "initial_slug": "$(json_escape "$P1_SLUG")",
        "initial_excerpt": "$(json_escape "$P1_EXCERPT")"
    },
    "p2": {
        "id": "$P2_ID",
        "initial_slug": "$(json_escape "$P2_SLUG")",
        "initial_excerpt": "$(json_escape "$P2_EXCERPT")"
    }
}
EOF

# 2. Prepare Environment (Firefox)
# Ensure WordPress admin is loaded. We want to start on the Products list page
# to save the agent one click and orient them immediately.
TARGET_URL="http://localhost/wp-admin/edit.php?post_type=product"

echo "Launching Firefox to Products list..."
if pgrep -f firefox > /dev/null; then
    pkill -f firefox
    sleep 2
fi

# Launch directly to product list
su - ga -c "DISPLAY=:1 firefox '$TARGET_URL' &"
sleep 10

# 3. Verify Window State
echo "Ensuring WordPress admin is displayed..."
if ! ensure_wordpress_shown 60; then
    echo "FATAL: Could not load WordPress admin page."
    exit 1
fi

# Focus and maximize
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    maximize_window "$WID"
fi

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="