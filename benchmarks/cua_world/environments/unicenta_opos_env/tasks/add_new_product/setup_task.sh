#!/bin/bash
echo "=== Setting up add_new_product task ==="

# Source shared utilities (do NOT use set -euo pipefail — pattern #25)
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
record_task_start /tmp/task_start_time.txt

# -----------------------------------------------------------------------
# Restore clean database state
# -----------------------------------------------------------------------
echo "Restoring clean database state..."
kill_unicenta
sleep 2

restore_database

# -----------------------------------------------------------------------
# Clean up any previous task artifacts
# -----------------------------------------------------------------------
echo "Cleaning up previous task artifacts..."

# Remove the target product if it exists from a previous run
unicenta_query "DELETE FROM products_cat WHERE product IN (SELECT id FROM products WHERE code='0048500202630');" 2>/dev/null || true
unicenta_query "DELETE FROM products WHERE code='0048500202630';" 2>/dev/null || true

# -----------------------------------------------------------------------
# Record initial product count (for delta-based verification — pattern #32)
# -----------------------------------------------------------------------
INITIAL_PRODUCT_COUNT=$(unicenta_query_value "SELECT COUNT(*) FROM products;")
echo "Initial product count: $INITIAL_PRODUCT_COUNT"
echo "$INITIAL_PRODUCT_COUNT" > /tmp/initial_product_count.txt

# Verify seed data is present
CATEGORY_COUNT=$(unicenta_query_value "SELECT COUNT(*) FROM categories;")
echo "Categories in database: $CATEGORY_COUNT"

if [ "$CATEGORY_COUNT" -lt 3 ]; then
    echo "WARNING: Seed data may not be fully loaded. Attempting to reload..."
    mysql -u unicenta -punicenta unicentaopos < /workspace/config/seed_data.sql 2>/dev/null || true
    CATEGORY_COUNT=$(unicenta_query_value "SELECT COUNT(*) FROM categories;")
    echo "Categories after reload: $CATEGORY_COUNT"
fi

# -----------------------------------------------------------------------
# Start uniCenta oPOS
# -----------------------------------------------------------------------
echo "Starting uniCenta oPOS..."
start_unicenta
sleep 5

# Take screenshot of initial state
take_screenshot /tmp/task_initial.png
echo "Initial state screenshot saved"

# Verify uniCenta is running
if pgrep -f "unicentaopos.jar" > /dev/null 2>&1; then
    echo "uniCenta oPOS is running"
else
    echo "WARNING: uniCenta oPOS may not be running"
fi

echo "=== add_new_product task setup complete ==="
