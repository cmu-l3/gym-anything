#!/bin/bash
echo "=== Setting up create_product_catalog task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (anti-gaming)
date +%s > /tmp/task_start_time.txt

# Clean any pre-existing test data (in case of retries)
echo "--- Cleaning pre-existing test data ---"
suitecrm_db_query "UPDATE aos_products SET deleted=1 WHERE name IN ('TempSense Pro X200', 'PressureGuard M500')" || true
suitecrm_db_query "UPDATE aos_products_categories SET deleted=1 WHERE name='Industrial Sensors'" || true

# Record initial counts
INITIAL_PRODUCT_COUNT=$(suitecrm_count "aos_products" "deleted=0")
INITIAL_CATEGORY_COUNT=$(suitecrm_count "aos_products_categories" "deleted=0")
echo "$INITIAL_PRODUCT_COUNT" > /tmp/initial_product_count.txt
echo "$INITIAL_CATEGORY_COUNT" > /tmp/initial_category_count.txt
echo "Initial products: $INITIAL_PRODUCT_COUNT, categories: $INITIAL_CATEGORY_COUNT"

# Ensure Firefox is running and logged in, then navigate to home
ensure_suitecrm_logged_in "http://localhost:8000/index.php?module=Home&action=index"

sleep 3

# Take screenshot of initial state
take_screenshot /tmp/task_initial_state.png

echo "=== Task setup complete ==="