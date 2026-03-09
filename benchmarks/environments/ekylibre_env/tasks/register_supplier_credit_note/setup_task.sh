#!/bin/bash
echo "=== Setting up register_supplier_credit_note task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming timestamp checks)
date +%s > /tmp/task_start_time.txt

# Wait for Ekylibre to be accessible
wait_for_ekylibre 120

# Record initial count of purchases to detect changes
# We query the purchases table
INITIAL_COUNT=$(docker exec ekylibre-db psql -U ekylibre -d ekylibre_production -t -A -c "SELECT COUNT(*) FROM purchases;" 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_purchase_count.txt
echo "Initial purchase count: $INITIAL_COUNT"

# Ensure Firefox is running and logged in
# Navigate to the Purchases list to give the agent a clear starting point
EKYLIBRE_URL=$(detect_ekylibre_url)
TARGET_URL="${EKYLIBRE_URL}/backend/purchases"

ensure_firefox_with_ekylibre "$TARGET_URL"
sleep 5

# Maximize window
maximize_firefox

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="