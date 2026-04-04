#!/bin/bash
# Export script for configure_multi_currency task

echo "=== Exporting configure_multi_currency Result ==="

. /workspace/scripts/task_utils.sh

# Fallback definitions
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

# 1. Check Currencies (Config Entities)
HAS_EUR="false"
HAS_GBP="false"

# Config names are 'commerce_price.commerce_currency.EUR'
if [ "$(drupal_db_query "SELECT COUNT(*) FROM config WHERE name = 'commerce_price.commerce_currency.EUR'")" -gt 0 ]; then
    HAS_EUR="true"
fi
if [ "$(drupal_db_query "SELECT COUNT(*) FROM config WHERE name = 'commerce_price.commerce_currency.GBP'")" -gt 0 ]; then
    HAS_GBP="true"
fi

# 2. Check Store Configuration
# Table: commerce_store__currencies, entity_id=1 (default store), currencies_target_id='EUR'
STORE_HAS_EUR="false"
STORE_HAS_GBP="false"

if [ "$(drupal_db_query "SELECT COUNT(*) FROM commerce_store__currencies WHERE entity_id=1 AND currencies_target_id='EUR'")" -gt 0 ]; then
    STORE_HAS_EUR="true"
fi
if [ "$(drupal_db_query "SELECT COUNT(*) FROM commerce_store__currencies WHERE entity_id=1 AND currencies_target_id='GBP'")" -gt 0 ]; then
    STORE_HAS_GBP="true"
fi

# 3. Check Products
# We need to find products with specific SKUs and check their prices/currencies
# Hierarchy: Product (Title) -> Variation (SKU, Price, Currency)

# Helper to get variation info by SKU
get_variation_info() {
    local sku="$1"
    # Returns: variation_id|price_number|currency_code|product_id|status
    drupal_db_query "SELECT variation_id, price__number, price__currency_code, product_id, status FROM commerce_product_variation_field_data WHERE sku='$sku'"
}

# Check EU Product
EU_INFO=$(get_variation_info "EU-TRAVEL-ADAPT")
EU_EXISTS="false"
EU_PRICE=""
EU_CURRENCY=""
EU_PUBLISHED="false"

if [ -n "$EU_INFO" ]; then
    EU_EXISTS="true"
    EU_PRICE=$(echo "$EU_INFO" | cut -f2)
    EU_CURRENCY=$(echo "$EU_INFO" | cut -f3)
    EU_PROD_ID=$(echo "$EU_INFO" | cut -f4)
    
    # Check if parent product is published
    if [ -n "$EU_PROD_ID" ]; then
        PROD_STATUS=$(drupal_db_query "SELECT status FROM commerce_product_field_data WHERE product_id=$EU_PROD_ID")
        if [ "$PROD_STATUS" == "1" ]; then
            EU_PUBLISHED="true"
        fi
    fi
fi

# Check UK Product
UK_INFO=$(get_variation_info "UK-AUDIO-CBL")
UK_EXISTS="false"
UK_PRICE=""
UK_CURRENCY=""
UK_PUBLISHED="false"

if [ -n "$UK_INFO" ]; then
    UK_EXISTS="true"
    UK_PRICE=$(echo "$UK_INFO" | cut -f2)
    UK_CURRENCY=$(echo "$UK_INFO" | cut -f3)
    UK_PROD_ID=$(echo "$UK_INFO" | cut -f4)
    
    if [ -n "$UK_PROD_ID" ]; then
        PROD_STATUS=$(drupal_db_query "SELECT status FROM commerce_product_field_data WHERE product_id=$UK_PROD_ID")
        if [ "$PROD_STATUS" == "1" ]; then
            UK_PUBLISHED="true"
        fi
    fi
fi

# Generate JSON Result
cat > /tmp/configure_multi_currency_result.json << EOF
{
    "has_eur_currency": $HAS_EUR,
    "has_gbp_currency": $HAS_GBP,
    "store_supports_eur": $STORE_HAS_EUR,
    "store_supports_gbp": $STORE_HAS_GBP,
    "eu_product": {
        "exists": $EU_EXISTS,
        "price": "${EU_PRICE:-0}",
        "currency": "${EU_CURRENCY:-}",
        "published": $EU_PUBLISHED
    },
    "uk_product": {
        "exists": $UK_EXISTS,
        "price": "${UK_PRICE:-0}",
        "currency": "${UK_CURRENCY:-}",
        "published": $UK_PUBLISHED
    },
    "timestamp": $(date +%s)
}
EOF

# Set permissions so verifier can read it
chmod 644 /tmp/configure_multi_currency_result.json 2>/dev/null || true

echo "Export complete. Result:"
cat /tmp/configure_multi_currency_result.json