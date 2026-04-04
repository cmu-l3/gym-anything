#!/bin/bash
set -e
echo "=== Setting up Configure Product Settings Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Verify database connectivity
check_db_connection || { echo "DB not ready"; exit 1; }

# CRITICAL: Ensure WordPress admin page is showing (not blank Firefox tab)
echo "Ensuring WordPress admin page is displayed..."
if ! ensure_wordpress_shown 60; then
    echo "FATAL: Could not load WordPress admin page - task cannot proceed"
    exit 1
fi

# Reset settings to "US/Permissive" defaults (Starting State)
# We set them to the OPPOSITE of the goal to ensure the agent actually changes them.
echo "Resetting product settings to initial state..."

# Cart behavior: No redirect, AJAX enabled
wp option update woocommerce_cart_redirect_after_add "no" --allow-root 2>&1
wp option update woocommerce_enable_ajax_add_to_cart "yes" --allow-root 2>&1

# Measurements: Imperial
wp option update woocommerce_weight_unit "lbs" --allow-root 2>&1
wp option update woocommerce_dimension_unit "in" --allow-root 2>&1

# Reviews: Permissive but enabled
wp option update woocommerce_enable_reviews "yes" --allow-root 2>&1
wp option update woocommerce_review_rating_verification_label "no" --allow-root 2>&1
wp option update woocommerce_review_rating_verification_required "no" --allow-root 2>&1
wp option update woocommerce_enable_review_rating "yes" --allow-root 2>&1
wp option update woocommerce_review_rating_required "no" --allow-root 2>&1

# Clear cache to ensure settings are reflected immediately
wp cache flush --allow-root 2>&1

# Record initial state for verifier anti-gaming check
cat > /tmp/initial_settings.json << EOF
{
  "woocommerce_cart_redirect_after_add": "no",
  "woocommerce_enable_ajax_add_to_cart": "yes",
  "woocommerce_weight_unit": "lbs",
  "woocommerce_dimension_unit": "in",
  "woocommerce_enable_reviews": "yes",
  "woocommerce_review_rating_verification_label": "no",
  "woocommerce_review_rating_verification_required": "no",
  "woocommerce_enable_review_rating": "yes",
  "woocommerce_review_rating_required": "no"
}
EOF

# Ensure the browser is focused on the dashboard to start
# The agent will need to navigate to Settings > Products
echo "Navigating Firefox to Dashboard..."
su - ga -c "DISPLAY=:1 firefox 'http://localhost/wp-admin/' &"
sleep 5

# Focus and maximize Firefox window
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task Setup Complete ==="