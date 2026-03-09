#!/bin/bash
# Setup script for organize_product_taxonomy task
set -e
echo "=== Setting up organize_product_taxonomy ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure services are running
ensure_services_running 90

# ==============================================================================
# CLEAN STATE: Remove any existing vocabulary or field to ensure agent does work
# ==============================================================================
echo "Ensuring clean state..."

# Check if vocabulary exists and delete it
if [ -d "/var/www/html/drupal" ]; then
    cd /var/www/html/drupal
    
    # Check/Delete field first (dependency)
    if ./vendor/bin/drush field:info commerce_product field_category > /dev/null 2>&1; then
        echo "Deleting existing field_category..."
        ./vendor/bin/drush field:delete commerce_product field_category -y > /dev/null 2>&1 || true
    fi

    # Check/Delete vocabulary
    # We use config:get because vocab check via drush might vary by version
    if ./vendor/bin/drush config:get taxonomy.vocabulary.product_categories > /dev/null 2>&1; then
        echo "Deleting existing product_categories vocabulary..."
        ./vendor/bin/drush entity:delete taxonomy_vocabulary product_categories -y > /dev/null 2>&1 || true
    fi
    
    # Clear cache to ensure UI reflects deletion
    ./vendor/bin/drush cr > /dev/null 2>&1
fi

# ==============================================================================
# BROWSER SETUP
# ==============================================================================
echo "Setting up browser..."

# Ensure Drupal admin is reachable
if ! ensure_drupal_shown 60; then
    echo "WARNING: Could not confirm Drupal admin page"
fi

# Navigate to Taxonomy overview page to save agent a click
navigate_firefox_to "http://localhost/admin/structure/taxonomy"
sleep 5

# Focus and maximize
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="