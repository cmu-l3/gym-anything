#!/bin/bash
set -e
echo "=== Setting up Organize Category Hierarchy Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Check database connectivity
if ! check_db_connection; then
    echo "ERROR: Database not reachable. Waiting..."
    sleep 5
    check_db_connection || exit 1
fi

# ==============================================================================
# CLEAN STATE: Remove categories if they already exist to prevent gaming
# ==============================================================================
echo "Ensuring clean state (removing target categories if they exist)..."

# Delete categories by name if they exist
for cat_name in "Tops" "Bottoms" "Apparel"; do
    EXISTING=$(get_category_by_name "$cat_name")
    if [ -n "$EXISTING" ]; then
        CAT_ID=$(echo "$EXISTING" | cut -f1)
        echo "Removing existing category '$cat_name' (ID: $CAT_ID)..."
        # Delete relationships first
        wc_query "DELETE FROM wp_term_relationships WHERE term_taxonomy_id IN (SELECT term_taxonomy_id FROM wp_term_taxonomy WHERE term_id = $CAT_ID)"
        # Delete taxonomy
        wc_query "DELETE FROM wp_term_taxonomy WHERE term_id = $CAT_ID"
        # Delete term
        wc_query "DELETE FROM wp_terms WHERE term_id = $CAT_ID"
    fi
done

# Record initial category count
INITIAL_CAT_COUNT=$(get_category_count 2>/dev/null || echo "0")
echo "$INITIAL_CAT_COUNT" > /tmp/initial_category_count.txt
echo "Initial category count: $INITIAL_CAT_COUNT"

# ==============================================================================
# APPLICATION SETUP
# ==============================================================================

# Ensure WordPress admin page is displayed
echo "Ensuring WordPress admin page is displayed..."
if ! ensure_wordpress_shown 60; then
    echo "FATAL: Could not load WordPress admin page"
    exit 1
fi

# Navigate Firefox to Categories page to help agent start
echo "Navigating to Product Categories page..."
su - ga -c "DISPLAY=:1 firefox --new-tab 'http://localhost/wp-admin/edit-tags.php?taxonomy=product_cat&post_type=product' &"
sleep 5

# Focus and maximize Firefox window
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
fi

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="