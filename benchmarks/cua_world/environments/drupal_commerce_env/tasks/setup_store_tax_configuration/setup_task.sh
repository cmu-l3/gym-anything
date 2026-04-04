#!/bin/bash
# Setup script for setup_store_tax_configuration task
echo "=== Setting up setup_store_tax_configuration ==="

. /workspace/scripts/task_utils.sh

if ! type drupal_db_query &>/dev/null; then
    drupal_db_query() {
        docker exec drupal-mariadb mysql -u drupal -pdrupalpass drupal -N -e "$1" 2>/dev/null
    }
    take_screenshot() {
        local path="${1:-/tmp/screenshot.png}"
        DISPLAY=:1 scrot "$path" 2>/dev/null || DISPLAY=:1 import -window root "$path" 2>/dev/null || true
    }
fi

ensure_services_running 120

# Record baseline state

# Store timezone (should be UTC initially)
INITIAL_TIMEZONE=$(drupal_db_query "SELECT timezone FROM commerce_store_field_data WHERE store_id=1")
INITIAL_TIMEZONE=${INITIAL_TIMEZONE:-UTC}
echo "$INITIAL_TIMEZONE" > /tmp/initial_store_timezone
echo "Initial timezone: $INITIAL_TIMEZONE"

# Store address line1 (should be '456 Market Street')
INITIAL_ADDRESS=$(drupal_db_query "SELECT address__address_line1 FROM commerce_store_field_data WHERE store_id=1")
echo "$INITIAL_ADDRESS" > /tmp/initial_store_address
echo "Initial address: $INITIAL_ADDRESS"

# Tax registrations (likely empty initially)
INITIAL_TAX_REGS=$(drupal_db_query "SELECT COUNT(*) FROM commerce_store__tax_registrations WHERE entity_id=1")
INITIAL_TAX_REGS=${INITIAL_TAX_REGS:-0}
echo "$INITIAL_TAX_REGS" > /tmp/initial_tax_registrations
echo "Initial tax registrations: $INITIAL_TAX_REGS"

# User count
INITIAL_USER_COUNT=$(drupal_db_query "SELECT COUNT(*) FROM users_field_data WHERE uid > 0")
INITIAL_USER_COUNT=${INITIAL_USER_COUNT:-0}
echo "$INITIAL_USER_COUNT" > /tmp/initial_user_count
echo "Initial user count: $INITIAL_USER_COUNT"

# Ensure taxmanager doesn't already exist (clean state)
EXISTING_TAX=$(drupal_db_query "SELECT COUNT(*) FROM users_field_data WHERE name='taxmanager'")
if [ "$EXISTING_TAX" -gt 0 ] 2>/dev/null; then
    echo "WARNING: taxmanager already exists, removing..."
    cd /var/www/html/drupal && vendor/bin/drush user:cancel --delete-content taxmanager -y 2>/dev/null || true
fi

# Store default currency
INITIAL_CURRENCY=$(drupal_db_query "SELECT default_currency FROM commerce_store_field_data WHERE store_id=1")
echo "$INITIAL_CURRENCY" > /tmp/initial_store_currency
echo "Initial currency: $INITIAL_CURRENCY"

# Record timestamp
date +%s > /tmp/task_start_timestamp

# Navigate to store admin
navigate_firefox_to "http://localhost/admin/commerce/config/stores"
sleep 5

take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="
