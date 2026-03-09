#!/bin/bash
# Export script for Table Rate Shipping task

echo "=== Exporting Table Rate Shipping Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# =============================================================================
# 1. VERIFY CONFIGURATION (Scope Check)
# =============================================================================
# We specifically need to check the 'websites' scope (scope_id = 1 usually for Main Website)
# checking 'default' scope is NOT sufficient for this task as import only works on website scope.

echo "Checking configuration for Website Scope (ID: 1)..."

# Check Active status
CONFIG_ACTIVE=$(magento_query "SELECT value FROM core_config_data WHERE path = 'carriers/tablerate/active' AND scope = 'websites' AND scope_id = 1" 2>/dev/null)

# Check Title
CONFIG_TITLE=$(magento_query "SELECT value FROM core_config_data WHERE path = 'carriers/tablerate/title' AND scope = 'websites' AND scope_id = 1" 2>/dev/null)

# Check Condition Name
CONFIG_CONDITION=$(magento_query "SELECT value FROM core_config_data WHERE path = 'carriers/tablerate/condition_name' AND scope = 'websites' AND scope_id = 1" 2>/dev/null)

echo "Config Found: Active=$CONFIG_ACTIVE, Title=$CONFIG_TITLE, Condition=$CONFIG_CONDITION"

# =============================================================================
# 2. VERIFY IMPORTED RATES
# =============================================================================
echo "Checking imported rates in shipping_tablerate table..."

# Get all rates for website_id = 1
# Format: dest_country_id | condition_value (weight) | price
RATES_RAW=$(magento_query "SELECT dest_country_id, condition_value, price FROM shipping_tablerate WHERE website_id = 1 ORDER BY condition_value ASC" 2>/dev/null)

# Convert raw rates to JSON array
RATES_JSON="[]"
if [ -n "$RATES_RAW" ]; then
    # Use python to safely format the SQL output into JSON
    RATES_JSON=$(python3 -c "
import sys
import json

lines = sys.stdin.read().strip().split('\n')
rates = []
for line in lines:
    if not line: continue
    parts = line.split('\t')
    if len(parts) >= 3:
        rates.append({
            'country': parts[0],
            'weight': float(parts[1]),
            'price': float(parts[2])
        })
print(json.dumps(rates))
" <<< "$RATES_RAW")
fi

echo "Rates found: $RATES_JSON"

# =============================================================================
# 3. CREATE RESULT JSON
# =============================================================================

# Escape strings for JSON
TITLE_ESC=$(echo "$CONFIG_TITLE" | sed 's/"/\\"/g')
CONDITION_ESC=$(echo "$CONFIG_CONDITION" | sed 's/"/\\"/g')

TEMP_JSON=$(mktemp /tmp/tablerate_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "config_active": "${CONFIG_ACTIVE:-0}",
    "config_title": "${TITLE_ESC:-}",
    "config_condition": "${CONDITION_ESC:-}",
    "imported_rates": $RATES_JSON,
    "timestamp": "$(date -Iseconds)"
}
EOF

safe_write_json "$TEMP_JSON" /tmp/table_rate_shipping_result.json

echo ""
cat /tmp/table_rate_shipping_result.json
echo ""
echo "=== Export Complete ==="