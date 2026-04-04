#!/bin/bash
# Export script for Currency Setup task

echo "=== Exporting Currency Setup Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Get initial state
INITIAL_ALLOWED=$(cat /tmp/initial_allowed_currencies 2>/dev/null || echo "")

# 1. Check Allowed Currencies
echo "Checking allowed currencies..."
CURRENT_ALLOWED=$(magento_query "SELECT value FROM core_config_data WHERE path = 'currency/options/allow'" 2>/dev/null || echo "")
echo "Allowed currencies: $CURRENT_ALLOWED"

# 2. Check Default Display Currency
echo "Checking default display currency..."
CURRENT_DEFAULT=$(magento_query "SELECT value FROM core_config_data WHERE path = 'currency/options/default'" 2>/dev/null || echo "")
echo "Default currency: $CURRENT_DEFAULT"

# 3. Check Base Currency (Safety check - shouldn't change)
CURRENT_BASE=$(magento_query "SELECT value FROM core_config_data WHERE path = 'currency/options/base'" 2>/dev/null || echo "")
echo "Base currency: $CURRENT_BASE"

# 4. Check Exchange Rates
echo "Checking exchange rates..."
# Get all rates from USD
RATES_DATA=$(magento_query "SELECT currency_to, rate FROM directory_currency_rate WHERE currency_from = 'USD'" 2>/dev/null)

# Parse rates into a JSON object string manually
# Format: {"EUR": 0.92, "GBP": 0.79, ...}
RATES_JSON="{"
count=0
while IFS=$'\t' read -r curr rate; do
    if [ -n "$curr" ] && [ -n "$rate" ]; then
        if [ $count -gt 0 ]; then RATES_JSON="$RATES_JSON, "; fi
        RATES_JSON="$RATES_JSON\"$curr\": $rate"
        count=$((count+1))
    fi
done <<< "$RATES_DATA"
RATES_JSON="$RATES_JSON}"

echo "Rates found: $RATES_JSON"

# Create JSON result
TEMP_JSON=$(mktemp /tmp/currency_setup_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "initial_allowed": "$INITIAL_ALLOWED",
    "current_allowed": "$CURRENT_ALLOWED",
    "current_default": "$CURRENT_DEFAULT",
    "current_base": "$CURRENT_BASE",
    "rates": $RATES_JSON,
    "export_timestamp": "$(date -Iseconds)"
}
EOF

safe_write_json "$TEMP_JSON" /tmp/currency_setup_result.json

echo ""
cat /tmp/currency_setup_result.json
echo ""
echo "=== Export Complete ==="