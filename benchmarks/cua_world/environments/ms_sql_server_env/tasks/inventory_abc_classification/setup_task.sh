#!/bin/bash
# Setup for inventory_abc_classification task
echo "=== Setting up Inventory ABC Classification Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# ============================================================
# Clean up any previous task artifacts
# ============================================================
echo "Cleaning up previous task artifacts..."

# Drop view if exists
mssql_query "
IF OBJECT_ID('Inventory.vw_ABC_Classification_2013', 'V') IS NOT NULL
    DROP VIEW Inventory.vw_ABC_Classification_2013
" "AdventureWorks2022"

# Drop schema if exists
mssql_query "
IF EXISTS (SELECT * FROM sys.schemas WHERE name = 'Inventory')
    DROP SCHEMA Inventory
" "AdventureWorks2022"

# Prepare export directory
mkdir -p /home/ga/Documents/exports
rm -f /home/ga/Documents/exports/class_a_priority.csv
chown -R ga:ga /home/ga/Documents
chmod 755 /home/ga/Documents/exports

# ============================================================
# Record initial state
# ============================================================
echo "Recording initial state..."
date +%s > /tmp/task_start_time.txt

# Record Total Product Count (Ground Truth for "Unsold Included" check)
TOTAL_PRODUCTS=$(mssql_query "SELECT COUNT(*) FROM Production.Product" | tr -d ' \r\n')
echo "Total products: $TOTAL_PRODUCTS" > /tmp/initial_state.txt

# ============================================================
# Ensure Azure Data Studio is running and connected
# ============================================================
echo "Ensuring Azure Data Studio is running..."

if ! pgrep -f "azuredatastudio" > /dev/null; then
    ADS_CMD="/snap/bin/azuredatastudio"
    [ ! -x "$ADS_CMD" ] && ADS_CMD="azuredatastudio"
    su - ga -c "DISPLAY=:1 $ADS_CMD > /tmp/ads.log 2>&1 &"
    
    # Wait for window
    for i in {1..30}; do
        if DISPLAY=:1 wmctrl -l | grep -qi "azure\|data studio"; then
            echo "ADS window detected"
            break
        fi
        sleep 1
    done
fi

sleep 5

# Maximize window
WID=$(DISPLAY=:1 wmctrl -l | grep -i "azure\|data studio" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Dismiss dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 0.5
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Connect to SQL Server
echo "Establishing SQL Connection..."
DISPLAY=:1 xdotool key F1
sleep 1
DISPLAY=:1 xdotool type 'new connection'
sleep 1
DISPLAY=:1 xdotool key Return
sleep 2

# Fill connection details
DISPLAY=:1 xdotool mousemove 1740 690 click 1; sleep 0.2; DISPLAY=:1 xdotool key ctrl+a; DISPLAY=:1 xdotool type 'localhost'
DISPLAY=:1 xdotool mousemove 1740 755 click 1; sleep 0.2; DISPLAY=:1 xdotool type 'sa'
DISPLAY=:1 xdotool mousemove 1740 785 click 1; sleep 0.2; DISPLAY=:1 xdotool type 'GymAnything#2024'
DISPLAY=:1 xdotool mousemove 1740 905 click 1; sleep 0.5; DISPLAY=:1 xdotool key t Return
sleep 1
DISPLAY=:1 xdotool mousemove 1770 1049 click 1
sleep 3

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="