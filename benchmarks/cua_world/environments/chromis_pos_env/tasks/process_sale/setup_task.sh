#!/bin/bash
echo "=== Setting up process_sale task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
echo "task_start_ts=$(date +%s)" > /tmp/task_start_time.txt

# Ensure MariaDB is running
ensure_mariadb

# Verify product data exists
PRODUCT_COUNT=$(chromis_query "SELECT COUNT(*) FROM PRODUCTS")
echo "Products in database: $PRODUCT_COUNT"

# Verify our target products exist
TARGET1=$(chromis_query "SELECT NAME FROM PRODUCTS WHERE NAME LIKE '%White Hanging Heart%' LIMIT 1")
TARGET2=$(chromis_query "SELECT NAME FROM PRODUCTS WHERE NAME LIKE '%Regency Cakestand%' LIMIT 1")
echo "Target product 1: $TARGET1"
echo "Target product 2: $TARGET2"

# Kill any running Chromis instance
kill_chromis 2>/dev/null || true

# Launch Chromis POS
launch_chromis

# Wait for the window
wait_for_chromis 120

# Give the app time to fully load the login screen
sleep 15

# Dismiss any startup dialogs
dismiss_dialogs
sleep 3

# The POS should show a login screen with user buttons
# Try to click the first user/admin button or enter default PIN
# Default admin PIN in Chromis is typically "0" or the admin button is visible
DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority xdotool key Return 2>/dev/null || true
sleep 3

# Focus and maximize the window
focus_chromis
maximize_chromis
sleep 2

# Take screenshot of the initial task state
take_screenshot /tmp/task_initial_state.png

echo "=== process_sale task setup complete ==="
echo "Agent should see the Chromis POS sales screen."
echo "Target items: 'White Hanging Heart T-Light Holder' and 'Regency Cakestand 3 Tier'"
