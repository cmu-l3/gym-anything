#!/bin/bash
# Setup script for architect_digital_products
echo "=== Setting up architect_digital_products ==="

source /workspace/scripts/task_utils.sh

# 1. Ensure services are running
ensure_services_running 120

# 2. Timestamp for anti-gaming
date +%s > /tmp/task_start_time.txt

# 3. Ensure Drupal is ready and we are logged in
if ! ensure_drupal_shown 60; then
    echo "Drupal not shown, forcing navigation..."
fi

# 4. Navigate to Commerce Configuration as a helpful starting point
# This puts the user near where they need to be (Commerce > Configuration)
navigate_firefox_to "http://localhost/admin/commerce/config"
sleep 5

# 5. Maximize window
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# 6. Take initial screenshot
take_screenshot /tmp/task_initial.png

# 7. cleanup any pre-existing config if this was a dirty env (safety check)
# In a clean env this does nothing, but good for robustness.
# We won't actually delete via DB as that's dangerous in Drupal without clearing cache.
# We'll just record that they didn't exist at start.
drupal_db_query "SELECT name FROM config WHERE name IN ('taxonomy.vocabulary.file_formats', 'commerce_product.commerce_product_variation_type.digital_variation')" > /tmp/pre_existing_config.txt

echo "=== Setup complete ==="