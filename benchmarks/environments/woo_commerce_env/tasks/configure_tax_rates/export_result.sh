#!/bin/bash
set -e
echo "=== Exporting Configure Tax Rates Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Output file
RESULT_FILE="/tmp/task_result.json"

# 1. Fetch Tax Options from wp_options
cd /var/www/html/wordpress
OPT_PRICES_INCLUDE=$(wp option get woocommerce_prices_include_tax --allow-root 2>/dev/null || echo "unknown")
OPT_CALC_BASED=$(wp option get woocommerce_tax_based_on --allow-root 2>/dev/null || echo "unknown")
OPT_DISPLAY_SHOP=$(wp option get woocommerce_tax_display_shop --allow-root 2>/dev/null || echo "unknown")
OPT_DISPLAY_CART=$(wp option get woocommerce_tax_display_cart --allow-root 2>/dev/null || echo "unknown")

# 2. Fetch Tax Rates from database
# We fetch relevant columns and format them as JSON objects
# Note: tax_rate_class '' indicates Standard rates
echo "Querying tax rates..."
RATES_JSON=$(wc_query "SELECT CONCAT(
    '{',
    '\"id\":\"', tax_rate_id, '\",',
    '\"country\":\"', tax_rate_country, '\",',
    '\"state\":\"', tax_rate_state, '\",',
    '\"rate\":\"', tax_rate, '\",',
    '\"name\":\"', tax_rate_name, '\",',
    '\"priority\":\"', tax_rate_priority, '\",',
    '\"compound\":\"', tax_rate_compound, '\",',
    '\"shipping\":\"', tax_rate_shipping, '\"',
    '}'
) 
FROM wp_woocommerce_tax_rates 
WHERE tax_rate_class = '' 
ORDER BY tax_rate_state ASC" 2>/dev/null | paste -sd, -)

# Wrap rates in array brackets
RATES_JSON="[${RATES_JSON:-}]"

# 3. Check for Anti-Gaming (Timestamp check)
# Since SQL doesn't track creation time for these rows by default, we rely on 
# the fact that we cleared the table in setup. Any rows present now are new.
# We also check the final screenshot existence.
SCREENSHOT_EXISTS="false"
if [ -f "/tmp/task_final.png" ]; then
    SCREENSHOT_EXISTS="true"
fi

# 4. Construct Final JSON
# Use python to construct safe JSON to avoid bash escaping hell
python3 -c "
import json
import sys

data = {
    'options': {
        'woocommerce_prices_include_tax': '$OPT_PRICES_INCLUDE',
        'woocommerce_tax_based_on': '$OPT_CALC_BASED',
        'woocommerce_tax_display_shop': '$OPT_DISPLAY_SHOP',
        'woocommerce_tax_display_cart': '$OPT_DISPLAY_CART'
    },
    'rates': $RATES_JSON,
    'screenshot_exists': $SCREENSHOT_EXISTS,
    'timestamp': '$(date -Iseconds)'
}
print(json.dumps(data))
" > "$RESULT_FILE"

echo "Export complete. Result saved to $RESULT_FILE"
cat "$RESULT_FILE"