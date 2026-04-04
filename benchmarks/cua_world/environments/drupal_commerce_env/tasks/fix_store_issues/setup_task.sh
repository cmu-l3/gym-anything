#!/bin/bash
# Setup script for fix_store_issues task
# Introduces 4 specific configuration errors into the database

echo "=== Setting up fix_store_issues ==="

# Source shared utilities
. /workspace/scripts/task_utils.sh

# Fallback definition for database query if utils not loaded
if ! type drupal_db_query &>/dev/null; then
    drupal_db_query() {
        docker exec drupal-mariadb mysql -u drupal -pdrupalpass drupal -N -e "$1" 2>/dev/null
    }
fi

# Ensure services are running
ensure_services_running 120

echo "Introducing configuration errors..."

# 1. Unpublish 'Samsung Galaxy S24 Ultra'
# First ensure it exists (seed data might vary)
PRODUCT_ID=$(drupal_db_query "SELECT product_id FROM commerce_product_field_data WHERE title LIKE '%Samsung Galaxy S24 Ultra%' LIMIT 1")
if [ -z "$PRODUCT_ID" ]; then
    # If not found, create it or pick another product to break
    echo "Creating missing product for task..."
    # (Simplified creation via SQL if missing, though seed usually provides it)
    # Ideally we assume seed data is present. If strictly missing, we might fail setup, but let's try to grab ANY product if specific one missing
    PRODUCT_ID=$(drupal_db_query "SELECT product_id FROM commerce_product_field_data LIMIT 1")
fi

if [ -n "$PRODUCT_ID" ]; then
    # Rename it to ensure task consistency
    drupal_db_query "UPDATE commerce_product_field_data SET title = 'Samsung Galaxy S24 Ultra' WHERE product_id = $PRODUCT_ID"
    # Unpublish it
    drupal_db_query "UPDATE commerce_product_field_data SET status = 0 WHERE product_id = $PRODUCT_ID"
    echo "Broken: Samsung Galaxy S24 Ultra unpublished (ID: $PRODUCT_ID)"
else
    echo "CRITICAL WARNING: No products found to unpublish!"
fi

# 2. Break Store Email
# Find the default store
STORE_ID=$(drupal_db_query "SELECT store_id FROM commerce_store_field_data WHERE is_default = 1 LIMIT 1")
if [ -n "$STORE_ID" ]; then
    drupal_db_query "UPDATE commerce_store_field_data SET name = 'Urban Electronics', mail = 'stoer@urbanelectronics.com' WHERE store_id = $STORE_ID"
    echo "Broken: Store email set to typo (ID: $STORE_ID)"
fi

# 3. Expire Promotion
# Find a promotion to break
PROMO_ID=$(drupal_db_query "SELECT promotion_id FROM commerce_promotion_field_data LIMIT 1")
if [ -z "$PROMO_ID" ]; then
    # Create dummy promotion if none exists
    drupal_db_query "INSERT INTO commerce_promotion (uuid, promotion_id) VALUES (UUID(), 999)"
    drupal_db_query "INSERT INTO commerce_promotion_field_data (promotion_id, langcode, status, name, display_name, offer__target_plugin_id, start_date) VALUES (999, 'en', 1, 'Electronics 15% Off', '15% Off', 'order_percentage_off', '2023-01-01')"
    PROMO_ID=999
fi
# Set end date to past
drupal_db_query "UPDATE commerce_promotion_field_data SET name = 'Electronics 15% Off', end_date = '2024-01-01', status = 1 WHERE promotion_id = $PROMO_ID"
echo "Broken: Promotion set to expired (ID: $PROMO_ID)"

# 4. Block User 'mikewilson'
# Ensure user exists
USER_ID=$(drupal_db_query "SELECT uid FROM users_field_data WHERE name = 'mikewilson'")
if [ -z "$USER_ID" ]; then
    # Create user if missing (should be in seed, but safe fallback)
    # Using drush for user creation is safer but SQL is faster for setup
    cd /var/www/html/drupal && vendor/bin/drush user:create mikewilson --mail="mike.wilson@example.com" --password="Customer123!" >/dev/null 2>&1
    USER_ID=$(drupal_db_query "SELECT uid FROM users_field_data WHERE name = 'mikewilson'")
fi
drupal_db_query "UPDATE users_field_data SET status = 0 WHERE uid = $USER_ID"
echo "Broken: User mikewilson blocked (ID: $USER_ID)"

# Record task start time
date +%s > /tmp/task_start_time.txt

# Record initial states for verification comparison
# We record the BROKEN state as the initial state
cat > /tmp/initial_broken_state.json << EOF
{
    "product_status": 0,
    "store_email": "stoer@urbanelectronics.com",
    "promo_end_date": "2024-01-01",
    "user_status": 0
}
EOF

# Open Firefox to Admin Dashboard
echo "Opening Drupal Admin..."
navigate_firefox_to "http://localhost/admin/commerce"
sleep 5

# Capture initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Setup Complete ==="