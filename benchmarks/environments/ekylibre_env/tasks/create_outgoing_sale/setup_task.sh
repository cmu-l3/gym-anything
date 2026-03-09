#!/bin/bash
set -e
echo "=== Setting up task: create_outgoing_sale ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Wait for Ekylibre to be accessible
wait_for_ekylibre 120

# Record initial sale count for comparison
INITIAL_SALES=$(ekylibre_db_query "SELECT COUNT(*) FROM sales;" 2>/dev/null || echo "0")
echo "$INITIAL_SALES" > /tmp/initial_sales_count.txt
echo "Initial sales count: $INITIAL_SALES"

# Record initial sale_items count
INITIAL_ITEMS=$(ekylibre_db_query "SELECT COUNT(*) FROM sale_items;" 2>/dev/null || echo "0")
echo "$INITIAL_ITEMS" > /tmp/initial_sale_items_count.txt

# Get the Ekylibre URL
EKYLIBRE_ACTIVE_URL=$(detect_ekylibre_url)

# Ensure Firefox is open and logged in, starting at the dashboard or commerce list
# We start at the backend root to force the agent to navigate
ensure_firefox_with_ekylibre "${EKYLIBRE_ACTIVE_URL}/backend"
sleep 5

# Maximize Firefox
maximize_firefox

# Take initial state screenshot
take_screenshot /tmp/task_initial_state.png

echo "=== Task setup complete ==="