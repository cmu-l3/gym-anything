#!/bin/bash
set -e
echo "=== Setting up add_farm_equipment task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Wait for Ekylibre to be fully accessible
wait_for_ekylibre 120

# Clean state: Remove any existing records matching the target name to prevent false positives
echo "Ensuring clean state..."
ekylibre_db_query "DELETE FROM products WHERE name ILIKE '%Massey Ferguson 7720%';" 2>/dev/null || true

# Record initial product count (all products)
INITIAL_PRODUCT_COUNT=$(ekylibre_db_query "SELECT count(*) FROM products;" 2>/dev/null || echo "0")
# Trim whitespace
INITIAL_PRODUCT_COUNT=$(echo "$INITIAL_PRODUCT_COUNT" | tr -d '[:space:]')
echo "$INITIAL_PRODUCT_COUNT" > /tmp/initial_product_count.txt
echo "Initial total product count: $INITIAL_PRODUCT_COUNT"

# Ensure Firefox is open with Ekylibre dashboard
EKYLIBRE_URL=$(detect_ekylibre_url)
# Navigate to the backend dashboard to start
ensure_firefox_with_ekylibre "${EKYLIBRE_URL}/backend"
sleep 5

# Maximize Firefox window
maximize_firefox
sleep 1

# Take initial state screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="
echo "Task: Register 'Massey Ferguson 7720' tractor with work number 'MF-7720-01'"