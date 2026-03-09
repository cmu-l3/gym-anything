#!/bin/bash
# Setup script for Enrich Product Fields task
echo "=== Setting up enrich_product_fields task ==="

source /workspace/scripts/task_utils.sh

# Fallback DB query function if not in utils
if ! type drupal_db_query &>/dev/null; then
    drupal_db_query() {
        docker exec drupal-mariadb mysql -u drupal -pdrupalpass drupal -N -e "$1" 2>/dev/null
    }
fi

# Ensure services are running
ensure_services_running 120

# 1. Cleanup: Ensure 'Brands' vocabulary and fields do not exist yet
# This ensures a clean slate for the agent
echo "Cleaning up any existing task artifacts..."

# Check and delete 'field_brand' config if exists
drupal_db_query "DELETE FROM config WHERE name LIKE '%field_brand%'"
drupal_db_query "DROP TABLE IF EXISTS commerce_product__field_brand"
drupal_db_query "DROP TABLE IF EXISTS commerce_product_revision__field_brand"

# Check and delete 'field_weight' config if exists
drupal_db_query "DELETE FROM config WHERE name LIKE '%field_weight%'"
drupal_db_query "DROP TABLE IF EXISTS commerce_product__field_weight"
drupal_db_query "DROP TABLE IF EXISTS commerce_product_revision__field_weight"

# Check and delete 'brands' vocabulary
drupal_db_query "DELETE FROM taxonomy_vocabulary WHERE vid = 'brands'"
drupal_db_query "DELETE FROM config WHERE name LIKE 'taxonomy.vocabulary.brands'"
# Delete terms associated with 'brands' (though vid link is broken now)
# We can't easily delete terms without VID link in a simple query safely, 
# but effectively the vocabulary is gone.

# Clear Drupal cache to reflect manual DB changes (this is aggressive but needed for clean state)
# We use drush to rebuild cache
cd /var/www/html/drupal
vendor/bin/drush cr > /dev/null 2>&1

# 2. Record initial state
date +%s > /tmp/task_start_timestamp

# 3. Prepare Browser
# Navigate to the Structure page where they can find Taxonomy and Content/Product types
navigate_firefox_to "http://localhost/admin/structure"
sleep 5

# Focus and maximize
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
fi

take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="