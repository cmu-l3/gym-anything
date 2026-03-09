#!/bin/bash
# Export script for setup_store_tax_configuration task
echo "=== Exporting setup_store_tax_configuration Result ==="

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

take_screenshot /tmp/task_end_screenshot.png

# Clear cache
cd /var/www/html/drupal && vendor/bin/drush cr 2>/dev/null || true

# Get baseline
INITIAL_TIMEZONE=$(cat /tmp/initial_store_timezone 2>/dev/null || echo "UTC")
INITIAL_ADDRESS=$(cat /tmp/initial_store_address 2>/dev/null || echo "456 Market Street")
INITIAL_TAX_REGS=$(cat /tmp/initial_tax_registrations 2>/dev/null || echo "0")
INITIAL_USER_COUNT=$(cat /tmp/initial_user_count 2>/dev/null || echo "0")
INITIAL_CURRENCY=$(cat /tmp/initial_store_currency 2>/dev/null || echo "USD")

# Query current store state
STORE_DATA=$(drupal_db_query "SELECT timezone, address__address_line1, default_currency, address__locality, address__administrative_area FROM commerce_store_field_data WHERE store_id=1")

CURRENT_TIMEZONE=$(echo "$STORE_DATA" | cut -f1)
CURRENT_ADDRESS=$(echo "$STORE_DATA" | cut -f2)
CURRENT_CURRENCY=$(echo "$STORE_DATA" | cut -f3)
CURRENT_CITY=$(echo "$STORE_DATA" | cut -f4)
CURRENT_STATE=$(echo "$STORE_DATA" | cut -f5)

# Check tax registrations
CURRENT_TAX_REGS=$(drupal_db_query "SELECT COUNT(*) FROM commerce_store__tax_registrations WHERE entity_id=1")
CURRENT_TAX_REGS=${CURRENT_TAX_REGS:-0}

TAX_REG_COUNTRIES=$(drupal_db_query "SELECT tax_registrations_value FROM commerce_store__tax_registrations WHERE entity_id=1" | tr '\n' ',' | sed 's/,$//')

# Check for taxmanager user
TAX_USER=$(drupal_db_query "SELECT uid, name, mail, status FROM users_field_data WHERE name='taxmanager'")
TAX_USER_FOUND="false"
TAX_USER_NAME=""
TAX_USER_EMAIL=""
TAX_USER_STATUS=""

if [ -n "$TAX_USER" ]; then
    TAX_USER_FOUND="true"
    TAX_USER_NAME=$(echo "$TAX_USER" | cut -f2)
    TAX_USER_EMAIL=$(echo "$TAX_USER" | cut -f3)
    TAX_USER_STATUS=$(echo "$TAX_USER" | cut -f4)
fi

# Check current user count
CURRENT_USER_COUNT=$(drupal_db_query "SELECT COUNT(*) FROM users_field_data WHERE uid > 0")
CURRENT_USER_COUNT=${CURRENT_USER_COUNT:-0}

# Check if commerce_tax module is enabled
TAX_MODULE_ENABLED="false"
MODULE_CHECK=$(drupal_db_query "SELECT name FROM config WHERE name='core.extension'" 2>/dev/null)
# Alternative: use drush
TAX_MODULE_DRUSH=$(cd /var/www/html/drupal && vendor/bin/drush pm:list --type=module --status=enabled --format=list 2>/dev/null | grep -c "commerce_tax" || echo "0")
if [ "$TAX_MODULE_DRUSH" -gt 0 ]; then
    TAX_MODULE_ENABLED="true"
fi

# Compute changes
TIMEZONE_CHANGED="false"
if [ "$CURRENT_TIMEZONE" != "$INITIAL_TIMEZONE" ]; then
    TIMEZONE_CHANGED="true"
fi

ADDRESS_CHANGED="false"
if [ "$CURRENT_ADDRESS" != "$INITIAL_ADDRESS" ]; then
    ADDRESS_CHANGED="true"
fi

cat > /tmp/setup_store_tax_configuration_result.json << EOF
{
    "initial_timezone": "$(echo "$INITIAL_TIMEZONE" | tr -d '\n\r')",
    "current_timezone": "$(echo "$CURRENT_TIMEZONE" | tr -d '\n\r')",
    "timezone_changed": $TIMEZONE_CHANGED,
    "initial_address": "$(echo "$INITIAL_ADDRESS" | tr -d '\n\r')",
    "current_address": "$(echo "$CURRENT_ADDRESS" | tr -d '\n\r')",
    "address_changed": $ADDRESS_CHANGED,
    "current_city": "$(echo "$CURRENT_CITY" | tr -d '\n\r')",
    "current_state": "$(echo "$CURRENT_STATE" | tr -d '\n\r')",
    "current_currency": "$(echo "$CURRENT_CURRENCY" | tr -d '\n\r')",
    "initial_tax_registrations": $INITIAL_TAX_REGS,
    "current_tax_registrations": $CURRENT_TAX_REGS,
    "tax_reg_countries": "$(echo "$TAX_REG_COUNTRIES" | tr -d '\n\r')",
    "tax_user_found": $TAX_USER_FOUND,
    "tax_user_name": "$(echo "$TAX_USER_NAME" | tr -d '\n\r')",
    "tax_user_email": "$(echo "$TAX_USER_EMAIL" | tr -d '\n\r')",
    "tax_user_status": ${TAX_USER_STATUS:-0},
    "initial_user_count": $INITIAL_USER_COUNT,
    "current_user_count": $CURRENT_USER_COUNT,
    "tax_module_enabled": $TAX_MODULE_ENABLED,
    "export_timestamp": "$(date -Iseconds)"
}
EOF

echo "Result JSON:"
cat /tmp/setup_store_tax_configuration_result.json
echo "=== Export Complete ==="
