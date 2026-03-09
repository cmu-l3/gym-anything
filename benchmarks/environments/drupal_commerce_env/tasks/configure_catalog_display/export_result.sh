#!/bin/bash
# Export script for Configure Catalog Display task
echo "=== Exporting Configure Catalog Display Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Export the current configuration for Product Display
# Config object: core.entity_view_display.commerce_product.default.default
echo "Exporting Product Display config..."
cd /var/www/html/drupal
PRODUCT_CONFIG=$(vendor/bin/drush cget core.entity_view_display.commerce_product.default.default --format=json 2>/dev/null)

# Export the current configuration for Variation Display
# Config object: core.entity_view_display.commerce_product_variation.default.default
echo "Exporting Variation Display config..."
VARIATION_CONFIG=$(vendor/bin/drush cget core.entity_view_display.commerce_product_variation.default.default --format=json 2>/dev/null)

# Create a combined JSON result file
# We use python to merge these safely into a single JSON object to avoid string escaping hell in bash
python3 -c "
import json
import sys

try:
    prod_config = json.loads('''$PRODUCT_CONFIG''')
except:
    prod_config = {}

try:
    var_config = json.loads('''$VARIATION_CONFIG''')
except:
    var_config = {}

result = {
    'product_display': prod_config,
    'variation_display': var_config,
    'timestamp': '$(date -Iseconds)'
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
"

# Set permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result JSON saved to /tmp/task_result.json"
cat /tmp/task_result.json

echo "=== Export Complete ==="