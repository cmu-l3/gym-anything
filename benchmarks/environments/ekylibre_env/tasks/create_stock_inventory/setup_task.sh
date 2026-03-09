#!/bin/bash
# Setup script for create_stock_inventory task

echo "=== Setting up Create Stock Inventory Task ==="

source /workspace/scripts/task_utils.sh

# 1. Wait for Ekylibre to be ready
wait_for_ekylibre 120

# 2. Record initial state (anti-gaming)
echo "Recording initial inventory count..."
# Query the inventories table count
INITIAL_COUNT=$(ekylibre_db_query "SELECT COUNT(*) FROM inventories")
echo "${INITIAL_COUNT:-0}" > /tmp/initial_inventory_count.txt
echo "Initial count: ${INITIAL_COUNT:-0}"

# Record start timestamp
date +%s > /tmp/task_start_time.txt

# 3. Open Firefox at Dashboard
# We want the agent to find the Stock menu, so we start at the main dashboard
EKYLIBRE_BASE=$(detect_ekylibre_url)
DASHBOARD_URL="${EKYLIBRE_BASE}/backend"

ensure_firefox_with_ekylibre "$DASHBOARD_URL"
sleep 5

# 4. Maximize window for visibility
maximize_firefox

# 5. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="
echo "Starting at: $DASHBOARD_URL"
echo "Goal: Create inventory 'Year-End Stock Count Jan 2024' with 2+ items"