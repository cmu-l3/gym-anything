#!/bin/bash
# Export script for deploy_customer_order_history_view
echo "=== Exporting deploy_customer_order_history_view Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot (should be of the user profile page if agent followed instructions)
take_screenshot /tmp/task_end_screenshot.png

# Get Jane's UID
JANE_UID=$(cat /tmp/janesmith_uid 2>/dev/null || echo "3")
INITIAL_USER_ORDER_COUNT=$(cat /tmp/initial_user_order_count 2>/dev/null || echo "0")

# 1. Check if View exists and export its config
VIEW_CONFIG_JSON="{}"
VIEW_EXISTS="false"
if drush config:get views.view.my_recent_orders > /dev/null 2>&1; then
    VIEW_EXISTS="true"
    # Export view config as JSON
    VIEW_CONFIG_JSON=$(drush config:get views.view.my_recent_orders --format=json)
else
    # Try finding by partial name if exact match failed
    POSSIBLE_VIEW=$(drush config:list --prefix=views.view | grep "recent_orders" | head -n 1)
    if [ -n "$POSSIBLE_VIEW" ]; then
        VIEW_EXISTS="true"
        VIEW_CONFIG_JSON=$(drush config:get "$POSSIBLE_VIEW" --format=json)
        echo "Found view with different name: $POSSIBLE_VIEW"
    fi
fi

# 2. Check if Block is placed and export its config
# The block config ID usually follows pattern block.block.views_block__[view_name]_[display_id]
# We'll look for any block config that mentions our view
BLOCK_CONFIG_JSON="{}"
BLOCK_PLACED="false"
BLOCK_ID=$(drush config:list --prefix=block.block | grep "my_recent_orders" | head -n 1)

if [ -n "$BLOCK_ID" ]; then
    BLOCK_PLACED="true"
    BLOCK_CONFIG_JSON=$(drush config:get "$BLOCK_ID" --format=json)
    echo "Found block placement: $BLOCK_ID"
fi

# 3. Check Order Data (Did agent create a test order?)
CURRENT_USER_ORDER_COUNT=$(drupal_db_query "SELECT COUNT(*) FROM commerce_order WHERE uid=$JANE_UID")
CURRENT_USER_ORDER_COUNT=${CURRENT_USER_ORDER_COUNT:-0}
ORDERS_CREATED=$((CURRENT_USER_ORDER_COUNT - INITIAL_USER_ORDER_COUNT))

# 4. Check if agent visited the user page (URL check via firefox window title or history if we could)
# We'll rely on the screenshot and the order creation for this.

# Construct Result JSON
# We embed the raw config JSONs into our result structure
# Use python to construct safe JSON to avoid escaping hell in bash
python3 -c "
import json
import sys

try:
    view_config = json.loads('''$VIEW_CONFIG_JSON''') if '$VIEW_EXISTS' == 'true' else {}
    block_config = json.loads('''$BLOCK_CONFIG_JSON''') if '$BLOCK_PLACED' == 'true' else {}
except:
    view_config = {}
    block_config = {}

result = {
    'view_exists': '$VIEW_EXISTS' == 'true',
    'view_config': view_config,
    'block_placed': '$BLOCK_PLACED' == 'true',
    'block_config': block_config,
    'initial_orders': int('$INITIAL_USER_ORDER_COUNT'),
    'current_orders': int('$CURRENT_USER_ORDER_COUNT'),
    'orders_created': int('$ORDERS_CREATED'),
    'test_uid': int('$JANE_UID')
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f)
"

chmod 666 /tmp/task_result.json

echo "=== Export Complete ==="