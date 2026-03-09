#!/bin/bash
echo "=== Exporting Configure International Settings Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Configuration for WP-CLI
CD_CMD="cd /var/www/html/wordpress"
WP_CMD="wp --allow-root --format=json"

# Helper to get option safely
get_wp_option() {
    local key="$1"
    # We use python to ensure we capture valid JSON even if WP-CLI outputs extra text
    # or if the option is empty.
    $CD_CMD && $WP_CMD option get "$key" 2>/dev/null || echo "null"
}

echo "Fetching current settings..."

# Fetch all relevant options
OPT_ALLOWED_COUNTRIES=$(get_wp_option "woocommerce_allowed_countries")
OPT_SPECIFIC_COUNTRIES=$(get_wp_option "woocommerce_specific_allowed_countries")
OPT_SHIP_TO=$(get_wp_option "woocommerce_ship_to_countries")
OPT_CURRENCY=$(get_wp_option "woocommerce_currency")
OPT_CURRENCY_POS=$(get_wp_option "woocommerce_currency_pos")
OPT_THOUSAND_SEP=$(get_wp_option "woocommerce_price_thousand_sep")
OPT_DECIMAL_SEP=$(get_wp_option "woocommerce_price_decimal_sep")

# Create JSON result
# Note: OPT_SPECIFIC_COUNTRIES is already a JSON array/object string from WP-CLI
TEMP_JSON=$(mktemp /tmp/settings_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "woocommerce_allowed_countries": $OPT_ALLOWED_COUNTRIES,
    "woocommerce_specific_allowed_countries": $OPT_SPECIFIC_COUNTRIES,
    "woocommerce_ship_to_countries": $OPT_SHIP_TO,
    "woocommerce_currency": $OPT_CURRENCY,
    "woocommerce_currency_pos": $OPT_CURRENCY_POS,
    "woocommerce_price_thousand_sep": $OPT_THOUSAND_SEP,
    "woocommerce_price_decimal_sep": $OPT_DECIMAL_SEP,
    "export_timestamp": "$(date -Iseconds)"
}
EOF

# Move to standard location
safe_write_json "$TEMP_JSON" /tmp/task_result.json

echo ""
echo "Exported settings:"
cat /tmp/task_result.json
echo ""
echo "=== Export Complete ==="