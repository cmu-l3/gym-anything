#!/bin/bash
# Export script for Configure Checkout Terms task
echo "=== Exporting Configure Checkout Terms Result ==="

source /workspace/scripts/task_utils.sh

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Find the created Terms page
# We look for the most recently created node with the expected title
EXPECTED_TITLE="Terms and Conditions"
NODE_JSON=$(drupal_db_query "SELECT nid, title, status FROM node_field_data WHERE title LIKE '%Terms and Conditions%' ORDER BY nid DESC LIMIT 1" | awk '{printf "{\"nid\": \"%s\", \"title\": \"%s\", \"status\": \"%s\"}", $1, $2, $3}')

if [ -z "$NODE_JSON" ] || [ "$NODE_JSON" == "{\"nid\": \"\", \"title\": \"\", \"status\": \"\"}" ]; then
    NODE_JSON="null"
fi

# 3. Get the Checkout Flow configuration using Drush
# This returns the full config object including enabled panes and their settings
cd /var/www/html/drupal
CHECKOUT_CONFIG_JSON=$(vendor/bin/drush config:get commerce_checkout.commerce_checkout_flow.default --format=json 2>/dev/null)

if [ -z "$CHECKOUT_CONFIG_JSON" ]; then
    CHECKOUT_CONFIG_JSON="{}"
fi

# 4. Get anti-gaming timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 5. Construct Result JSON
# We use python to safely construct JSON to avoid bash quoting hell with nested JSON
python3 -c "
import json
import sys

try:
    node_data = $NODE_JSON if $NODE_JSON is not None else None
    checkout_config = json.loads('''$CHECKOUT_CONFIG_JSON''')
    
    result = {
        'node_data': node_data,
        'checkout_config': checkout_config,
        'task_start': $TASK_START,
        'task_end': $TASK_END
    }
    
    with open('/tmp/task_result.json', 'w') as f:
        json.dump(result, f, indent=2)
        
except Exception as e:
    print(f'Error constructing result JSON: {e}')
    # Fallback empty JSON
    with open('/tmp/task_result.json', 'w') as f:
        f.write('{}')
"

# 6. Permission fix
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result JSON saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="