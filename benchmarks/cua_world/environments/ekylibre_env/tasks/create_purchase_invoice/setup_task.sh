#!/bin/bash
echo "=== Setting up create_purchase_invoice task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming)
date +%s > /tmp/task_start_time.txt

# Record initial purchase invoice count
echo "Recording initial invoice count..."
INITIAL_COUNT=$(docker exec ekylibre-db psql -U ekylibre -d ekylibre_production -t -A -c "SELECT COUNT(*) FROM purchases WHERE type = 'PurchaseInvoice';" 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_invoice_count.txt
echo "Initial count: $INITIAL_COUNT"

# Ensure Ekylibre is running and accessible
wait_for_ekylibre 120

# Open Firefox to the Dashboard (Agent must navigate themselves)
EKYLIBRE_URL=$(detect_ekylibre_url)
ensure_firefox_with_ekylibre "$EKYLIBRE_URL/backend"
sleep 5

# Maximize window
maximize_firefox

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="