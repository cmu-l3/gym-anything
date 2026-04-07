#!/bin/bash
echo "=== Setting up update_product_price task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
echo "task_start_ts=$(date +%s)" > /tmp/task_start_time.txt

# Ensure MariaDB is running
ensure_mariadb

# Reset the target product price to its original value (in case of repeated runs)
chromis_query "UPDATE PRODUCTS SET PRICESELL=2.47 WHERE NAME LIKE '%Jumbo Bag Red Retrospot%'" 2>/dev/null || true

# Verify the product exists and show current state
CURRENT_PRICE=$(chromis_query "SELECT PRICESELL FROM PRODUCTS WHERE NAME LIKE '%Jumbo Bag Red Retrospot%' LIMIT 1")
echo "Target product: Jumbo Bag Red Retrospot"
echo "Current sell price: $CURRENT_PRICE (should be 2.47)"
echo "Target sell price: 3.99"

# Kill any running Chromis instance
kill_chromis 2>/dev/null || true

# Launch Chromis POS
launch_chromis

# Wait for the window
wait_for_chromis 120

# Give the app time to fully load
sleep 15

# Dismiss any startup dialogs
dismiss_dialogs
sleep 3

# Try to log in
DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority xdotool key Return 2>/dev/null || true
sleep 3

# Focus and maximize the window
focus_chromis
maximize_chromis
sleep 2

# Take screenshot of the initial task state
take_screenshot /tmp/task_initial_state.png

echo "=== update_product_price task setup complete ==="
echo "Agent should see Chromis POS main screen."
echo "Agent needs to navigate to Stock > Products, find 'Jumbo Bag Red Retrospot', change price to 3.99"
