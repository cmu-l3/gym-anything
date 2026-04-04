#!/bin/bash
# Setup script for configure_multi_currency task

echo "=== Setting up configure_multi_currency ==="

# Source shared utilities
. /workspace/scripts/task_utils.sh

# Fallback definitions if utils aren't loaded
if ! type drupal_db_query &>/dev/null; then
    drupal_db_query() {
        docker exec drupal-mariadb mysql -u drupal -pdrupalpass drupal -N -e "$1" 2>/dev/null
    }
    take_screenshot() {
        local path="${1:-/tmp/screenshot.png}"
        DISPLAY=:1 scrot "$path" 2>/dev/null || DISPLAY=:1 import -window root "$path" 2>/dev/null || true
    }
    navigate_firefox_to() {
        local url="$1"
        DISPLAY=:1 xdotool key ctrl+l; sleep 0.5
        DISPLAY=:1 xdotool type --clearmodifiers "$url"; sleep 0.3
        DISPLAY=:1 xdotool key Return; sleep 3
    }
fi

# Ensure services are up
ensure_services_running 120

# Cleanup: Ensure clean state (remove currencies if they exist from previous runs)
echo "Cleaning up any existing EUR/GBP configurations..."
drupal_db_query "DELETE FROM config WHERE name IN ('commerce_price.commerce_currency.EUR', 'commerce_price.commerce_currency.GBP')"
drupal_db_query "DELETE FROM commerce_store__currencies WHERE currencies_target_id IN ('EUR', 'GBP')"
# We don't delete products to avoid breaking entity references broadly, but we check for existence
# If specific SKUs exist, we should probably delete the variations to allow clean creation
VAR_ID_EU=$(drupal_db_query "SELECT variation_id FROM commerce_product_variation_field_data WHERE sku='EU-TRAVEL-ADAPT'")
if [ -n "$VAR_ID_EU" ]; then
    echo "Warning: Cleaning up existing EU product variation..."
    # This is a bit risky in raw SQL without entity API, but okay for setup reset
    # Ideally we'd use drush php:eval, but let's just record initial state carefully
fi

# Record initial state
echo "Recording initial state..."
INITIAL_CURRENCY_COUNT=$(drupal_db_query "SELECT COUNT(*) FROM config WHERE name LIKE 'commerce_price.commerce_currency.%'")
echo "${INITIAL_CURRENCY_COUNT:-0}" > /tmp/initial_currency_count

INITIAL_STORE_CURRENCIES=$(drupal_db_query "SELECT COUNT(*) FROM commerce_store__currencies WHERE entity_id=1")
echo "${INITIAL_STORE_CURRENCIES:-0}" > /tmp/initial_store_currency_count

INITIAL_PRODUCT_COUNT=$(drupal_db_query "SELECT COUNT(*) FROM commerce_product_field_data")
echo "${INITIAL_PRODUCT_COUNT:-0}" > /tmp/initial_product_count

# Record timestamp
date +%s > /tmp/task_start_timestamp

# Ensure Firefox is open and logged in
if ! pgrep -f firefox > /dev/null; then
    su - ga -c "DISPLAY=:1 firefox &"
    sleep 5
fi

# Navigate to Commerce Configuration page to give a hint/head start
navigate_firefox_to "http://localhost/admin/commerce/config"
sleep 5

# Maximize window
WID=$(DISPLAY=:1 wmctrl -l | grep -i "firefox" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz
fi

take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="